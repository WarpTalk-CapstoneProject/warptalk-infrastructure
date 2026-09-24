# Data placement runbook: move Postgres, Redis and RabbitMQ to the Data node

Status: **plan only, nothing here has been executed.** Written 2026-09-24 against the live cluster.

## Why

Both Postgres instances, `warptalk-redis-node-0` and `warptalk-rabbitmq-server-0` run on the App
node. Their local-path volumes were first bound there, and a local-path PersistentVolume carries
node affinity, so these pods can never be scheduled anywhere else. On 24 Sep, with the App node's
memory requests at 99%, redis-node-0 could not come back after a restart: there was no Redis
master, and every AI worker crash-looped. The Data node (8 GiB, 2 vCPU) had 15% of its memory
requested.

Live placement on 2026-09-24:

| Claim | Size | Node |
| --- | --- | --- |
| `warptalk-data/warptalk-postgres-1` (primary) | 25Gi | App |
| `warptalk-data/warptalk-postgres-2` (standby) | 25Gi | App |
| `warptalk-data/redis-data-warptalk-redis-node-0` | 20Gi | App |
| `warptalk-data/redis-data-warptalk-redis-node-1` | 20Gi | Data |
| `warptalk-data/redis-data-warptalk-redis-node-2` | 20Gi | Data (orphaned: the StatefulSet has 2 replicas) |
| `warptalk/persistence-warptalk-rabbitmq-server-0` | 5Gi | App |
| `warptalk-data/qdrant-storage-warptalk-qdrant-0` | 50Gi | Data |

The method is the same for each store. Build a new member whose volume binds on the Data node,
move the role (primary or master) to it, and only then retire the App-node member. The App node
is **cordoned** for the short moment a new volume binds, so the scheduler has nowhere else to put
it. Cordoning evicts nothing, and running pods keep running. While the node is cordoned, a
scale-out stays Pending until you uncordon.

## Order and rules

0. The preconditions below. Each one blocks what comes after it.
1. Postgres (P1-P4). It has no downtime: CloudNativePG streams the new standby and switches over.
2. Redis (R0-R3). It has no downtime: every master move is a manual `SENTINEL FAILOVER`, which
   works even with two sentinels.
3. RabbitMQ (Q1-Q3). It needs a short maintenance window: a single broker cannot hand off.
4. Make placement hard, and update the capacity contract (F1).

- **Freeze releases** for the whole procedure: do not dispatch `release.yml`. Every step below
  leaves the values files unchanged until F1, so a release would not undo anything. The freeze
  exists so that a release cannot restart a pod while the App node is cordoned.
- Work with the admin kubeconfig: `export KUBECONFIG=~/.kube/config-warptalk-prod`.
- Before each step, read its Rollback section. Stop at the first verification that fails.

## Preconditions

**C1. The Data-node kubelet must be reachable from the API server.** Today `kubectl
logs/exec/port-forward` into any Data-node pod fails, because :10250 cannot be reached. Every
verification below reads logs or runs `exec` on the new member, which will be on the Data node.
Fix this first. The candidates are UFW on the Data VM for the control plane's tailnet address,
or a kubelet bound to an address the API server does not route to.
Verify: `kubectl logs -n warptalk-data warptalk-redis-node-1 -c redis --tail=5` returns lines.

**C2. Postgres backups must work.** They do not today. The `ContinuousArchiving` condition has
been `False` since 2026-09-19 12:03Z (`barman-cloud-wal-archive: exit status 4`), and every
`warptalk-postgres-daily-*` Backup since has failed. This means there is **no base backup and
no WAL archive to restore from**. It also means `pg_wal` on the primary cannot be recycled and
keeps growing. Fix the ObjectStore or its credentials, then take an on-demand backup:

```sh
kubectl get cluster -n warptalk-data warptalk-postgres \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'   # ContinuousArchiving=True
cat <<'EOF' | kubectl apply -f -
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: {name: warptalk-postgres-before-move, namespace: warptalk-data}
spec:
  cluster: {name: warptalk-postgres}
  method: plugin
  pluginConfiguration: {name: barman-cloud.cloudnative-pg.io}
EOF
kubectl get backup -n warptalk-data warptalk-postgres-before-move -w   # phase: completed
```

**C3. The deployer can manage the PriorityClass.** Apply `deploy/k3s/cluster/deployer-rbac.yaml`
server-side once. Without it, the next release stops at the data platform preflight:

```sh
kubectl apply --server-side -f deploy/k3s/cluster/deployer-rbac.yaml
```

The first release after this PR creates `warptalk-data-critical`. It also rolls Postgres once
onto that class and the 512Mi request: the standby restarts first, then the primary switches
over (`primaryUpdateMethod: switchover`). Expect a few seconds of write retries. Run that
release in a quiet hour.

**C4. The Data node has room.** Its target, with everything on it, is about 5.8 GiB of 8 GiB
(README "Capacity plan"). Check:
`kubectl describe node warptalk-data-node | sed -n '/Allocated resources/,/Events/p'`.

**C5. Tools.** You need the CloudNativePG kubectl plugin at the operator's version (1.30):
`kubectl krew install cnpg`, or the release binary from github.com/cloudnative-pg/cloudnative-pg.

## Postgres (CloudNativePG `warptalk-postgres`, 2 instances)

The instance count stays at 2 throughout, so `k8s-data-values.yaml` never disagrees with the
cluster. You retire an App-node instance with `cnpg destroy`, which removes the pod and its PVC.
The operator then creates a replacement instance to keep the count at 2. With the App node
cordoned, the replacement's volume binds on the Data node.

**P1. Replace the standby (`-2`) with one on the Data node.**

```sh
kubectl cnpg status warptalk-postgres -n warptalk-data   # primary -1, standby -2 streaming
kubectl cordon warptalk-app-worker
kubectl cnpg destroy warptalk-postgres 2 -n warptalk-data
# The operator creates warptalk-postgres-3 (a join Job, then the instance). Watch it bind:
kubectl get pvc -n warptalk-data warptalk-postgres-3 -w      # Bound
kubectl get pvc -n warptalk-data warptalk-postgres-3 \
  -o jsonpath='{.metadata.annotations.volume\.kubernetes\.io/selected-node}{"\n"}'  # warptalk-data-node
kubectl uncordon warptalk-app-worker
```

Uncordon as soon as the claim shows `selected-node: warptalk-data-node`. That is usually within
a minute.

- *Verify:* `kubectl cnpg status` shows `-3` as a streaming standby with replication lag near
  0. The cluster reports `Cluster in healthy state`. `kubectl get pod -n warptalk-data
  warptalk-postgres-3 -o wide` shows the pod on the Data node.
- *Risk window:* until `-3` is streaming, the primary is the only copy. That is why C2 comes
  first. `dataDurability: preferred` keeps writes going while no standby exists.
- *Rollback:* uncordon the App node. If `-3` cannot start on the Data node (Pending, or
  CrashLoop), run `kubectl cnpg destroy warptalk-postgres 3`, then cordon the **Data** node
  (`kubectl cordon warptalk-data-node`) so the operator's next replacement binds on the App node.
  Once it streams, uncordon the Data node. The primary is untouched throughout.

**P2. Switch over to the Data-node standby.**

```sh
kubectl cnpg promote warptalk-postgres warptalk-postgres-3 -n warptalk-data
```

- *Verify:* `kubectl get cluster -n warptalk-data warptalk-postgres` shows PRIMARY
  `warptalk-postgres-3`. `-1` is a streaming standby. The pooler still resolves
  `warptalk-postgres-rw`, and `kubectl get endpoints -n warptalk-data warptalk-postgres-rw`
  points at the pod IP of `-3`. The application stays healthy:
  `curl -fsS https://api.warptalk.io.vn/health/ready`, and
  `scripts/accept-k3s-release.sh` (read-only) passes. Watch 5xx on Grafana for 10 minutes.
- *Rollback:* `kubectl cnpg promote warptalk-postgres warptalk-postgres-1 -n warptalk-data`.

**P3. Replace the old primary (`-1`, now a standby) with one on the Data node.** This repeats
P1 with `destroy warptalk-postgres 1`. The replacement will be `-4`.

- *Verify:* the same checks as P1. Both instances (`-3` primary, `-4` standby) are on the Data
  node, and `kubectl get pvc -n warptalk-data` shows no Postgres claim on the App node.
- *Rollback:* the same as P1.

**P4. Close out.** Take a fresh on-demand backup, as in C2. Confirm that
`ContinuousArchiving=True`. Confirm that `kubectl get pv` no longer lists the two deleted
volumes; local-path's reclaim policy is Delete. If one is stuck in `Released`, delete it only
after checking that it belonged to `-1` or `-2`.

## Redis (bitnami `warptalk-redis`, Sentinel, 2 nodes)

With two nodes, each carrying a sentinel, and quorum 2, a failed master can never be replaced
automatically, because its own sentinel goes down with it. That is also why a restart of the
master is an outage. `SENTINEL FAILOVER` is the exception: it is a manual failover and needs no
agreement from other sentinels.

**R0. Restore the third node, if C1 made redis-node-2 debuggable.** Set `replica.replicaCount: 3`
in `deploy/k3s/data/redis-values.yaml` and release. redis-node-2's old claim is still bound on
the Data node. From then on, sentinel quorum 2 of 3 fails over on its own. This step is
recommended. It is not required by R1-R3.

**R1. Make redis-node-1 (on the Data node) the master.** Run this from node-0's sentinel. node-0 is
on the App node, so `exec` works there even before C1 is fixed.

```sh
auth='REDISCLI_AUTH="$(cat "$REDIS_PASSWORD_FILE")"'
kubectl exec -n warptalk-data warptalk-redis-node-0 -c sentinel -- sh -c \
  "$auth redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster"
kubectl exec -n warptalk-data warptalk-redis-node-0 -c sentinel -- sh -c \
  "$auth redis-cli -p 26379 SENTINEL FAILOVER mymaster"
```

`REDIS_PASSWORD` is empty in these containers. Use the password file, otherwise you get
WRONGPASS, which looks like a secret mismatch but is not one. If the sentinel answers
without auth, drop the prefix.

- *Verify:* `get-master-addr-by-name` now returns node-1's address. `INFO replication` on node-0
  shows `role:slave` and `master_link_status:up`. The workers stop logging reconnects within 30s,
  and `redis_stream_group_lag` in Grafana goes back down.
- *Rollback:* `SENTINEL FAILOVER mymaster` again. The master returns to node-0.

**R2. Recreate redis-node-0 on the Data node.**

```sh
kubectl cordon warptalk-app-worker
kubectl delete pvc -n warptalk-data redis-data-warptalk-redis-node-0 --wait=false
kubectl delete pod -n warptalk-data warptalk-redis-node-0
kubectl get pvc -n warptalk-data redis-data-warptalk-redis-node-0 -w   # re-created, Bound
kubectl get pod -n warptalk-data warptalk-redis-node-0 -o wide          # on warptalk-data-node
kubectl uncordon warptalk-app-worker
```

node-0 starts empty. It asks the sentinels for the master, which is now node-1, and runs a full
sync.

- *Verify:* `INFO replication` on node-1 (the master) shows `connected_slaves:1` and
  `state=online`. Both sentinels agree on the master. `kubectl get pvc -n warptalk-data -o
  wide` shows no Redis claim on the App node.
- *Rollback:* uncordon. If node-0 cannot start on the Data node, delete its new claim and pod
  with the **Data** node cordoned, so that it returns to the App node, then uncordon. node-1 keeps
  serving as master the whole time.

**R3. Assign the PriorityClass and the measured request.** redis p95 is 48Mi, so the request
becomes about 256Mi. Keep `maxmemory 640mb` and the 896Mi limit. Pod-template changes restart
the pods, and a plain rolling update restarts node-1, the master, first. So apply this change
with `OnDelete` and restart replica-first by hand:

```sh
# 1. In deploy/k3s/data/redis-values.yaml, under replica:
#      priorityClassName: warptalk-data-critical
#      resources.requests.memory: 256Mi
#    Then apply it without restarting anything:
. deploy/k3s/addons.lock.env
scripts/helm-locked.sh upgrade warptalk-redis bitnami/redis --version "$REDIS_CHART_VERSION" \
  --namespace warptalk-data -f deploy/k3s/data/redis-values.yaml \
  --set-string replica.persistence.storageClass=local-path \
  --set replica.updateStrategy.type=OnDelete --wait --timeout 15m
# 2. Restart the replica (node-0), and wait until it is Ready and in sync (INFO replication).
kubectl delete pod -n warptalk-data warptalk-redis-node-0
# 3. Move the master to node-0, then restart node-1.
kubectl exec ... SENTINEL FAILOVER mymaster      # as in R1
kubectl delete pod -n warptalk-data warptalk-redis-node-1
```

Merge the values change to `development`. The next release restores the `RollingUpdate`
strategy without restarting anything, because the pod template is unchanged.

- *Verify:* `kubectl get pod -n warptalk-data -l app.kubernetes.io/name=redis -o
  custom-columns=N:.metadata.name,P:.spec.priorityClassName,NODE:.spec.nodeName` shows
  `warptalk-data-critical` on both pods, and both on the Data node.
- *Rollback:* revert the values change. Repeat the same OnDelete sequence.

## RabbitMQ (`warptalk-rabbitmq`, 1 node, in namespace `warptalk`)

There is no zero-downtime path for a single broker. The Cluster Operator can add nodes but
cannot remove them, so "grow to 3, then drop the App-node member" is not available. Plan a
**5-minute window** at a quiet hour. Publishers (billing outbox, notifications, workspace events)
get connection errors for about 1-2 minutes. The billing outbox retries. Notifications published
inside the window may be lost.

**Q1. Drain.** Queues are quorum queues and live on the volume that is about to be replaced. Wait
until the queues are empty, and export the definitions. The broker is on the App node, so
`exec` works:

```sh
kubectl exec -n warptalk warptalk-rabbitmq-server-0 -c rabbitmq -- \
  rabbitmqctl list_queues name messages consumers
kubectl exec -n warptalk warptalk-rabbitmq-server-0 -c rabbitmq -- \
  rabbitmqctl export_definitions /tmp/defs.json
kubectl cp -c rabbitmq warptalk/warptalk-rabbitmq-server-0:/tmp/defs.json ./rabbitmq-defs.json
```

**Q2. Recreate the broker on the Data node.**

```sh
kubectl cordon warptalk-app-worker
kubectl delete pvc -n warptalk persistence-warptalk-rabbitmq-server-0 --wait=false
kubectl delete pod -n warptalk warptalk-rabbitmq-server-0
kubectl get pod -n warptalk warptalk-rabbitmq-server-0 -o wide -w   # Running on warptalk-data-node
kubectl uncordon warptalk-app-worker
```

The operator keeps the `warptalk-rabbitmq-default-user` Secret, so the services' credentials do
not change. The services declare their own topology when they reconnect. Import the exported
definitions anyway, so that nothing declared only once is lost. This needs C1:

```sh
kubectl cp -c rabbitmq ./rabbitmq-defs.json warptalk/warptalk-rabbitmq-server-0:/tmp/defs.json
kubectl exec -n warptalk warptalk-rabbitmq-server-0 -c rabbitmq -- \
  rabbitmqctl import_definitions /tmp/defs.json
```

- *Verify:* `kubectl get rabbitmqcluster -n warptalk warptalk-rabbitmq` reports
  `AllReplicasReady=True`. `rabbitmqctl list_queues name consumers` shows consumers on every
  queue. notification-service, workspace-service and billing-service logs show a reconnect and
  no repeating errors. Send one test notification end to end.
- *Rollback:* the old volume is gone, so rolling back means recreating the broker on the App
  node. Cordon the Data node, delete the new claim and pod, import `rabbitmq-defs.json`, then
  uncordon.

**Q3. Assign the PriorityClass and the measured request.** rabbitmq p95 is 117Mi, so the request
becomes about 160Mi. Set `rabbitmq.priorityClassName: warptalk-data-critical` and the request in
`deploy/k3s/k8s-data-values.yaml`. Assigning it restarts the broker, so do it inside the same
window: right after Q2 verifies, apply it with `scripts/deploy-k3s-data.sh` from that checkout
(one more pause of about a minute), then merge the change so releases carry it.

**Alternative with no window (not planned).** Run a second `RabbitmqCluster` on the Data node,
add a shovel from the old broker's queues to it, and switch `RabbitMq__Host` and the credentials
Secret in one release. This needs the broker name parametrised in both charts. It is worth doing
only if a 2-minute messaging pause is unacceptable.

## Qdrant

Qdrant is already on the Data node. To give it the class, set `priorityClassName:
warptalk-data-critical` in `deploy/k3s/data/qdrant-values.yaml`. With a single node, the restart
blanks semantic search for a few seconds, so do it in the RabbitMQ window.

## F1. Afterwards

- **Hard placement.** In `k8s-data-values.yaml` (`placement.nodeSelector:
  {node.warptalk.io/role: data}`), `data/redis-values.yaml` (`nodeAffinityPreset.type: hard`)
  and `data/qdrant-values.yaml`, pin the data tier to the Data node. It is safe now, because every
  claim is there.
- **Capacity contract.** In `scripts/check-k3s-deployment.sh`, empty `APP_NODE_DATA_PODS`, and
  update README "Capacity plan". The App node gains about 2.3 GiB of free requests.
- Delete the orphaned `redis-data-warptalk-redis-node-2` claim if R0 was not done.
- End the release freeze.
