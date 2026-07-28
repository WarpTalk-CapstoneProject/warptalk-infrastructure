# WarpTalk performance validation

`k6/warptalk.js` exercises the production-shaped gateway paths for:

- login;
- workspace listing;
- HTTP room joining;
- transcript retrieval;
- SignalR negotiate, WebSocket upgrade and JSON-protocol handshake.

The workload never creates data. Provision a dedicated verified user, workspace,
room membership and transcript fixture before running it.

```bash
docker run --rm \
  -e BASE_URL=http://host.docker.internal:5200 \
  -e PERF_EMAIL \
  -e PERF_PASSWORD \
  -e WORKSPACE_ID \
  -e ROOM_CODE \
  -e TRANSCRIPT_ID \
  -e PERF_DURATION=2m \
  -v "$PWD/performance/k6:/scripts:ro" \
  grafana/k6:0.57.0 run /scripts/warptalk.js
```

The default load is 14 concurrent VUs: 2 login, 8 API, 2 room joins and 2
SignalR clients. Increase one path at a time with `AUTH_VUS`, `API_VUS`,
`JOIN_VUS` and `SIGNALR_VUS`; record container CPU/RAM and database/queue
metrics during every run.

Production capacity is not inferred from laptop results. A staging run on the
chosen VM topology is the promotion gate, using the same script and immutable
release manifest.
