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
