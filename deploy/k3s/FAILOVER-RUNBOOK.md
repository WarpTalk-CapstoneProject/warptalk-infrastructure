# WarpTalk K3s failover runbook

## Declared objectives

- API availability: loss of one application node must retain at least one
  ready replica behind the external load balancer.
- PostgreSQL recovery point objective: a recovery window: 5 minutes, bounded
  by continuous WAL archive upload and `archive_timeout=5min`.
- PostgreSQL recovery time objective: 5 minutes for an automatic in-cluster
  primary failover; 30 minutes for point-in-time recovery into a new cluster.
- Redis/RabbitMQ/Qdrant: survive one data-node loss without acknowledged data
  loss when quorum remains.

These are deployment objectives, not claims about an unprovisioned provider.
They become accepted only after the drills below pass on the selected
multi-node infrastructure.

## Preflight

1. Confirm at least three App nodes and three failure-domain-separated Data
   nodes are Ready.
2. Confirm every API Deployment has two Ready replicas on different nodes and
   every PodDisruptionBudget allows at most one unavailable pod.
3. Confirm CloudNativePG reports one primary and two streaming replicas with
   synchronous replication healthy.
4. Confirm RabbitMQ queues are quorum queues, Redis Sentinel sees a master plus
   three replicas, and Qdrant collections use at least two shard replicas.
5. Confirm the latest base backup is valid and WAL objects are arriving less
   than five minutes apart.

## Application-node drill

1. Start a continuous authenticated API and SignalR probe from outside the
   cluster.
2. Drain one App node with eviction and wait for replacement pods.
3. Verify the external load balancer continues returning successful requests,
   SignalR reconnect succeeds, and no PDB is violated.
4. Uncordon the node and attach probe output plus pod scheduling events to the
   release evidence.

## PostgreSQL drill

1. Record the primary pod, replication delay and last archived WAL timestamp.
2. Delete only the primary pod. Do not delete PVCs.
3. Observe CloudNativePG promote a replica and update the read/write Service.
4. Run the logical-database boundary check and a write/read smoke test for all
   eight service databases.
5. Measure RTO from primary loss to the first successful application write.
6. Quarterly, restore the newest base backup plus WAL into an isolated cluster,
   run migrations in validation mode, and compare checksums/counts.

## Queue and vector drills

- RabbitMQ: terminate one node; verify quorum queues remain available and
  outbox events settle exactly once after recovery.
- Redis: terminate the master; verify Sentinel elects a replica, workers
  reconnect, pending entries remain reclaimable, and heartbeat alerts recover.
- Qdrant: terminate one pod; verify search/write at the configured consistency
  and restore a snapshot into an isolated collection.

## Abort criteria

Abort rollout and invoke the immutable release rollback when error rate is at
least 1%, p95 exceeds the release SLO for ten minutes, any acknowledged message
is lost, database replication loses quorum, or migrations cannot complete.
Never force quorum by discarding the surviving data set.

## Production on one Data VM

The three-VM production cluster (deploy/k3s/README.md, "Production on the three Vietnix
VMs") has a single Data node, so the quorum steps above apply to pod failures only. Losing the
Data VM itself is a restore:

- Postgres: CloudNativePG `bootstrap.recovery` from the Barman object store
  (`warptalk-postgres-backup`), RPO ~5 minutes (`archive_timeout`).
- Qdrant: the nightly `warptalk-qdrant-snapshot` CronJob uploads a full-storage snapshot to the
  same bucket; restore it with `POST /snapshots/recover` (or the chart's `snapshotRestoration`),
  or re-embed from Postgres if the snapshot is older than the documents that matter.
- Redis holds no durable state beyond AOF on the node; live meetings in progress are lost.
