# WarpTalk Health Inspector

One on-demand image checks the WarpTalk Compose runtime, readiness endpoints,
AI worker health, and recent container logs. It never runs as part of normal
startup because the Compose service is behind the `tools` profile.

On the current App, Data, and Infra production hosts, use the installed command:

```sh
warptalk-health-check
warptalk-health-check --since 30m --json
```

The command discovers the live Compose project and host network. The inspector
then auto-detects the App, Data, or Infra inventory and enforces the required
services for that host.

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
warning (recent restarts or suspicious log evidence), and `2` critical (missing,
stopped, unhealthy, OOM-killed, or failed application probe).

The Docker socket is mounted read-only. That limits accidental filesystem
changes, but access to a Docker socket is still host-privileged; run this image
only from the trusted operations host and do not expose it as a network service.
