# WarpTalk production security acceptance

This checklist maps the production release to the OWASP API Top 10 control
areas. It is an acceptance artefact, not a claim that automated checks replace
an independent penetration test.

| Risk area | Implemented control | Release evidence |
|---|---|---|
| Broken object authorization | JWT at the gateway; service-owned authorization and workspace/document access checks | Backend authorization tests and authenticated route smoke |
| Broken authentication | No production secret fallback; refresh-token family reuse detection; signing-key overlap rotation | `JwtKeyRotationTests`, `JWT-ROTATION-RUNBOOK.md` |
| Object/property authorization | Typed DTO validation; no direct client pricing trust in Billing | Backend contract/unit tests |
| Resource exhaustion | Chained IP, user and workspace rate limits; bounded request/message sizes and worker queues | `RequestRateLimitPartitionKeysTests`, production Compose limits |
| Function authorization | Admin routes require authenticated role policies in owning APIs | Controller integration tests; manual role-negative cases below |
| Sensitive business flows | Stripe signature verification, provider idempotency, outbox/inbox deduplication | Billing tests plus real Sandbox webhook acceptance |
| Server-side request forgery | Provider endpoints come from deployment configuration; document storage uses owned S3 endpoint | Environment contract review |
| Security misconfiguration | TLS, HSTS, secure headers, private data ports, no-new-privileges, non-root/read-only app containers | `check-production-deployment.sh`, `security-smoke.sh` |
| Inventory management | Versioned HTTP/gRPC/event contracts and event catalog compatibility CI | `contracts/events/catalog.json` |
| Unsafe API consumption | Internal gRPC auth, deadlines, bounded retries and circuit breaker | Internal gRPC tests |

## Required pre-demo negative tests

- A non-member cannot read, alter, approve, archive, or delete another
  workspace's document.
- A normal member cannot call admin notification or billing adjustment routes.
- Replaying the same Stripe event does not create a second credit transaction.
- A webhook with an invalid signature is rejected and does not write Billing.
- A reused refresh token revokes its entire rotation family.
- Oversized upload, SignalR message, pagination size, and AI queue pressure are
  rejected or bounded.
- PostgreSQL, Redis, RabbitMQ, MinIO, Qdrant and observability UIs are
  unreachable from a public network probe.
- Logs contain actor/workspace/route/outcome for admin, billing and document
  access, but no bearer token, provider secret, request body, or document text.

Run after each staging or production deployment:

```sh
APP_URL=https://app.warptalk.vn \
API_URL=https://api.warptalk.vn \
./scripts/security-smoke.sh
```
