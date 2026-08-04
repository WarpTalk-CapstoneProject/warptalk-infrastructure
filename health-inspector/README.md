# WarpTalk Health Inspector

One on-demand image checks the WarpTalk Compose runtime, readiness endpoints,
AI worker health, and recent container logs. It never runs as part of normal
startup because the Compose service is behind the `tools` profile.

On the current App, Data, and Infra production hosts, use the installed command:

```sh
warptalk-health-check
warptalk-health-check --since 30m --json
warptalk-health-check \
  --from 2026-08-01T04:30:00Z \
  --until 2026-08-01T05:30:00Z \
  --json
```

The command discovers the live Compose project and host network. The inspector
then auto-detects the App, Data, or Infra inventory and enforces the required
services for that host.

Repeated failures are grouped by a stable fingerprint while UUIDs, timestamps,
and changing numeric values are normalized. Each group reports its count,
first/last timestamp, and one redacted sample. The host command persists a
restart baseline in the dedicated Docker volume
`warptalk-health-inspector-state`, so an old restart does not remain a
permanent warning. An explicit historical scan with `--until` never overwrites
that current-state checkpoint.

## Local

```sh
docker compose --env-file .env.example --profile tools run --rm --build health-inspector --since 30m
```

## Production app host

Use the same environment file and release tag as the deployed app Compose
project:

```sh
docker compose \
  --env-file deploy/production/.env \
  -f deploy/production/app.compose.yml \
  --profile tools run --rm health-inspector --since 30m
```

Add `--json` for machine-readable output. Exit codes are `0` healthy, `1`
warning (new restarts since the prior check or suspicious log evidence), and
`2` critical (missing, stopped, unhealthy, OOM-killed, or failed application
probe).

The Docker socket is mounted read-only. That limits accidental filesystem
changes, but access to a Docker socket is still host-privileged; run this image
only from the trusted operations host and do not expose it as a network service.
