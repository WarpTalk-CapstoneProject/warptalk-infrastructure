# WarpTalk cost governance

WarpTalk separates infrastructure capacity from usage-priced providers:

- Enterprise Cloud compute, RAM, NVMe and floating IP are a fixed monthly
  infrastructure envelope.
- STT, translation, TTS, voice cloning and LiveKit are estimated from trailing
  30-day product usage.
- MinIO capacity is measured from bucket metrics.

The estimator is intentionally configuration-driven. Public list prices are
not embedded in source because provider, model, region, discount and contract
terms change. Before every production release, an operator must copy the
current signed-contract rates and approved budgets into `.env.production`,
render the configs and review the generated values.

## Render

From `warptalk-infrastructure`:

```sh
set -a
. deploy/production/.env.production
set +a
./scripts/render-cost-observability.sh
```

The renderer accepts only decimal values greater than zero, writes atomically and
sets generated files to mode `0600`. Generated files are deploy artifacts and
are not committed:

- `observability/billing-cost-queries.yml`
- `observability/livekit-cost-queries.yml`
- `observability/alerts/warptalk.cost.rules.yml`

Run the production contract after rendering:

```sh
./scripts/check-production-deployment.sh
```

## Metric sources

`billing-cost-exporter` connects to `warptalk_billing` as the non-superuser
`warptalk_monitor` role and may select only `subscription.usage_records`.
`livekit-cost-exporter` uses the same role against
`warptalk_translation_room` and may select only
`translation_room.translation_rooms` and artifact sizes.
`workspace-storage-exporter` may select only Workspace document sizes. All
three use SQL Exporter with one connection and a one-minute minimum query
interval.

The exported series are:

- `warptalk_ai_cost_30d{service,metric}` where `metric` is
  `usage_minutes`, `estimated_cost_usd`, `unit_cost_usd_per_minute`,
  `budget_usd`, or `credits_consumed`.
- `warptalk_livekit_cost_30d{metric}` where `metric` is `room_minutes`,
  `estimated_cost_usd`, `unit_cost_usd_per_room_minute`, or `budget_usd`.
- `warptalk_object_storage_bytes{source}` for active Workspace documents and
  Translation artifacts, plus `warptalk_object_storage_budget_bytes`.

The object storage capacity alerts are evaluated against
`minio_bucket_usage_total_bytes` from the `minio-buckets` scrape job, not
against `warptalk_object_storage_bytes`. The application-indexed series only
sums size columns of live database rows: it undercounts real stored bytes by
roughly an order of magnitude and never sees buckets that have no indexing
table behind them, including voice samples, meeting chat and LiveKit egress
recordings. A capacity budget has to be compared against bytes that are really
on the volume, so provider-neutrality is traded away here; moving to R2 or
another S3-compatible store means repointing those two rules at that
provider's usage metric.

`warptalk_object_storage_bytes{source}` remains exported and on the dashboard
as the logical view of storage per application domain. The gap between it and
the bucket totals is the orphaned-object and missing-metadata signal, and it
should still be reconciled against provider billing.

Because the capacity alerts now depend on a single scrape job,
`WarpTalkObjectStorageUsageMetricMissing` fires when that series disappears,
so losing the capacity signal is itself an alert rather than silence.

A zero rate or budget is rejected by the renderer: it is not a way to disable
an alert, it silently breaks one. A zero budget makes every comparison against
it true, and a zero unit rate makes the estimated-cost metric identically zero
so its budget alerts can never fire.

The usage ledger remains the billing source of truth. These Prometheus metrics
are estimates for operations and must not be used to create customer invoices.

## Alert policy

- Warning at more than 80% of each configured monthly provider budget.
- Critical at more than 100%.
- Object-storage warning/critical at 80%/100% of the configured capacity
  envelope.
- A zero budget is valid only when the corresponding feature is intentionally
  disabled; otherwise it causes any non-zero usage to alert immediately.

On a warning, verify the contract rate, identify the workspace/feature driving
usage and forecast month-end spend. On a critical alert, disable optional
voice-clone workloads or apply workspace quotas before raising the approved
budget. Never silently change a rate or budget merely to clear an alert.

## Monthly review

1. Reconcile estimated provider usage against provider invoices.
2. Record any unit mismatch (seconds, characters, tokens, room participants).
3. Update rates and rerender if the contract changed.
4. Review per-service budget utilization and MinIO growth.
5. Keep the approved infrastructure envelope at or below the project ceiling;
   provider usage is tracked separately because it scales with demo traffic.
