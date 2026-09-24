# Agent runbook: production error-log inspection

## Trigger

Treat **"kiểm tra log lỗi của prod"** and semantically equivalent requests such
as "check production errors", "đọc log prod", or "prod có lỗi gì" as an
instruction to run the deployed WarpTalk health inspector.

## Required scope

Run `/usr/local/bin/warptalk-health-check` on all three production roles:

1. App VM
2. Data VM
3. Infra VM

Never claim the whole production system was checked if any role was skipped.
Use the approved WarpTalk Vietnix access path and host inventory. Codex should
use the `warptalk-vietnix-ops` skill. Other agents must use the same approved
SSH/bastion path; they must not guess credentials or expose key material.

## Commands

For an unspecified current window, inspect the last 30 minutes on each VM:

```sh
warptalk-health-check --since 30m --json
```

If the user provides a time range, convert Asia/Ho_Chi_Minh time to RFC3339 UTC
and use a bounded historical scan:

```sh
warptalk-health-check \
  --from 2026-08-01T04:30:00Z \
  --until 2026-08-01T05:30:00Z \
  --json
```

Historical scans with `--until` do not update the restart checkpoint. Current
scans persist restart baselines in the Docker volume
`warptalk-health-inspector-state`.

## Kubernetes production (after the k8s cutover)

Production runs on Kubernetes and the release workflow deploys only there; the Docker Compose
commands above apply only to a host recovered onto compose by hand. On Kubernetes the three roles
are namespaces and nodes of one cluster, and the same inspector reads them through the API server
instead of the Docker socket:

```sh
KUBECONFIG=<read-only kubeconfig> \
  python3 health-inspector/inspector.py --platform k8s --role all --since 30m --json
```

- `--role all` covers App (namespace `warptalk`: every service and AI worker Deployment), Data
  (namespace `warptalk-data`: CloudNativePG, Redis, Qdrant; RabbitMQ in `warptalk`) and Infra
  (every node's conditions, `monitoring` and `traefik`). Report the three separately, as above.
- It needs only the `warptalk-inspector` ClusterRole from `deploy/k3s/cluster/deployer-rbac.yaml`
  (get/list pods, pods/log, nodes, workloads). It never execs into a pod.
- Every k8s release job already runs it once after acceptance and puts the JSON in the run's
  step summary, so the latest release's inspection is in the Actions run.
- `--from/--until` work as above; `--until` is applied to the log timestamps because
  `kubectl logs` has no end bound. Restart baselines use `--checkpoint <file>` as on Docker.
- Not covered in this mode: the in-container `shared.health_probe` exec (the pods' own
  liveness/startup probes run it continuously; a failure shows up as restarts or not-ready) and
  the WT-595 port-publication check (there is no host port publication on Kubernetes).

## Interpretation

- Exit `0`: no warning or critical result in that host scan.
- Exit `1`: warnings, new restarts, or suspicious log fingerprints exist.
- Exit `2`: critical state such as missing/stopped/unhealthy/OOM-killed
  container or failed application/worker probe.
- Read `logFindings` by service. Use fingerprint `count`, `firstSeen`,
  `lastSeen`, and redacted `sample`; do not list every duplicate line.
- Separate confirmed production issues from historical evidence and from
  inspector/runtime limitations.
- Report App, Data, and Infra separately, then give one prioritized system-wide
  summary.
- A health-only pass does not erase log findings. A warning is not automatically
  a service outage.

This workflow is read-only triage. Do not restart containers, edit production
configuration, clear logs, or fix findings unless the user separately asks for
that mutation.
