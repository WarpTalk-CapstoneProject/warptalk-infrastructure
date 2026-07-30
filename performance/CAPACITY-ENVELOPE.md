# WarpTalk capacity envelope

## Measured local baseline

Measured on 2026-07-27 with Docker Desktop on Apple Silicon (7.75 GiB Docker
memory), through the real gateway and logical databases. This is a regression
baseline, not a provider sizing certificate.

The 30-second k6 run used 14 virtual users across login, workspace listing,
translation-room join, transcript retrieval and SignalR negotiate/WebSocket
handshake:

| Result | Measured |
|---|---:|
| HTTP requests | 1,037 |
| Throughput | 33.46 requests/s |
| HTTP failure rate | 0% |
| Checks | 1,142 / 1,142 |
| Overall p95 | 63.58 ms |
| Login p95 | 155.82 ms |
| Room join p95 | 40.00 ms |
| Transcript p95 | 29.36 ms |
| Workspace list p95 | 38.20 ms |
| SignalR handshakes | 24 / 24 |

A second 20-second run produced 719 requests at 34.87 requests/s, 0% errors
and overall p95 56.79 ms. During that run:

| Component | Average CPU | Peak CPU | Memory |
|---|---:|---:|---:|
| Gateway | 3.12% | 4.76% | 73.48 MiB |
| Auth | 9.27% | 37.88% | 139.6 MiB |
| Workspace | 3.32% | 12.17% | 162.1 MiB |
| Translation room | 3.24% | 6.95% | 173.7 MiB |
| PostgreSQL | 3.75% | 7.86% | 229.7 MiB |
| PgBouncer | 0.57% | 1.25% | 2.18 MiB |
| Redis | 17.08% | 18.29% | 222.9 MiB |

The run exposed an O(number-of-room-streams) transcript poller consuming
roughly 150–163% CPU while idle. After switching persistence to the three
global result streams and adding idle backoff, warm idle samples were
1.01–2.34% CPU at about 95.8 MiB. This corrected implementation is the
capacity baseline.

A fresh 30-second run against the corrected transcript service produced 943
HTTP requests (29.77 requests/s) and 1,050 successful checks with zero HTTP
failures. All configured thresholds passed:

| Endpoint/result | Measured |
|---|---:|
| Overall p95 | 78.94 ms |
| Login p95 | 98.68 ms |
| Workspace list p95 | 54.78 ms |
| Room join p95 | 28.66 ms |
| Transcript p95 | 165.25 ms |
| SignalR connect/handshake | 24 / 24 |

The transcript container settled at 0.86% CPU and 184.4 MiB immediately after
the run, instead of returning to the previous runaway idle load. The raw k6
summary is retained locally as
`performance/results/phase2-post-transcript-fix.json` (the results directory is
intentionally excluded from source control).

The provider-free Redis Streams benchmark then queued 120 messages spanning
eight target languages against a worker capacity of four. It completed in
0.706 seconds (169.89 messages/s), never exceeded four active handlers,
observed peak Redis lag of 116 and peak pending of four, and finished with zero
pending messages. This proves excess work remains queued in Redis while the
bounded worker is saturated. The repeatable benchmark is
`warptalk-ai/benchmarks/queue_capacity.py`; it uses no paid provider calls and
deletes its isolated test stream on completion.

## Production starting envelope

The provider-neutral two-VM layout is:

| VM | Capacity | Primary role |
|---|---:|---|
| App | 8 vCPU, 17 GiB RAM, 60 GiB NVMe | Caddy, web, gateway, services, workers |
| Data | 4 vCPU, 13 GiB RAM, 90 GiB NVMe | PostgreSQL, queues, object/vector stores, observability |

PgBouncer permits 300 clients and allocates 15 normal plus 5 reserve server
connections per service database. Across eight service database/user pairs,
the maximum pool contribution is 160 PostgreSQL connections. PostgreSQL is
limited to 200, leaving 40 connections for migration, monitoring, maintenance
and failover operations.

## Release gates

Before promoting a provider release:

1. Run the k6 scenario from a separate staging load generator, never from the
   production VM.
2. Keep HTTP error rate below 1%, checks above 99%, API p95 below 500 ms,
   login p95 below 750 ms and SignalR handshake success above 99%.
3. Run for at least 15 minutes at expected demo concurrency, then 5 minutes at
   2x expected concurrency.
4. Verify no PostgreSQL pool exhaustion, Redis eviction, pending-stream growth,
   worker heartbeat loss or dead-letter growth.
5. Capture CPU, memory, disk latency, network and provider latency; attach the
   k6 JSON artifact to the release evidence.

## Scaling triggers

- Scale a stateless service horizontally when p95 breaches its SLO for 10
  minutes and CPU exceeds 70%, or when memory exceeds 80%.
- Scale AI worker replicas when consumer lag exceeds two minutes for five
  minutes; stop accepting optional workloads if lag continues to grow at the
  configured maximum replica count.
- Increase Data VM IOPS/RAM before increasing PostgreSQL connections when
  cache hit rate drops or disk latency rises.
- Add a read replica only for demonstrated read pressure; writes and migrations
  remain on the primary.
- Increase MinIO capacity before 80% utilization and validate the offsite
  backup/restore path after every storage change.

Provider staging validation remains mandatory because local Docker results do
not model the provider's CPU generation, noisy-neighbor behavior, NVMe latency,
private-network latency or external AI/LiveKit service latency.
