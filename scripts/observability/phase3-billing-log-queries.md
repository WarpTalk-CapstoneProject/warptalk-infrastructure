# Phase 3 Billing Observability Queries

Use these event names/keywords for staging dashboards and alert rules after deployment.

| Signal | Event id | Query keyword | Severity |
|---|---:|---|---|
| Usage settlement failed | 4101 | `billing_settlement_failed` | Critical |
| Billing event skipped because rate is missing | 4102 | `billing_event_skipped_missing_rate` | High |
| Billing cycle closed | 4103 | `billing_cycle_closed` | Info |
| Invoice overdue caused suspension | 4104 | `invoice_overdue_suspend` | High |
| AI service suspended by billing | 4105 | `AiServiceSuspended` | High |
| AI service manually resumed | 4106 | `Billing AI service resumed` | Audit |

## Suggested Alert Rules

| Alert | Rule |
|---|---|
| Settlement failure | Trigger when `billing_settlement_failed` count > 0 in 5 minutes. |
| Missing rate | Trigger when `billing_event_skipped_missing_rate` count > 0 in 5 minutes. |
| Invoice suspension spike | Trigger when `invoice_overdue_suspend` count >= 3 in 30 minutes. |
| No billing cycle close | Trigger when no `billing_cycle_closed` event appears for more than 26 hours in an active billing environment. |

## Staging Checks

1. Deploy migration 041.
2. Run settlement smoke and concurrency smoke.
3. Trigger one overdue invoice in staging demo data.
4. Confirm logs contain `invoice_overdue_suspend`.
5. Resume the workspace from API and confirm Redis `ai_service_suspended=false`.
