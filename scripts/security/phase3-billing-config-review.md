# Phase 3 Billing Config Security Review

Run this before staging and production rollout.

## Required Checks

| Check | Expected |
|---|---|
| `ConnectionStrings:BillingDb` | Comes from environment/secret store in staging/prod, not committed plain text. |
| `ConnectionStrings:Redis` or `Redis:ConnectionString` | Uses password/TLS when required by environment. |
| `Stripe:SecretKey` | Comes from secret store; no real key in `appsettings.json`. |
| `Jwt:Secret` | Comes from secret store and is at least 32 chars. |
| Billing worker intervals | `BillingCycleIntervalMinutes` and `InvoiceOverdueIntervalMinutes` configured per environment. |
| Migration order | Apply 038, 039, 040, then 041. |
| Rate card seed | Verify `provider`, `model`, `unit`, `unit_price` and `effective_from` before opening traffic. |
| Redis suspend keys | Confirm `workspace:{workspaceId}:ai_service_suspended` flips to `true/false`. |

## Local Commands

```powershell
rg -n "sk_live_|sk_test_|whsec_|password=|CHANGE_ME|placeholder" D:\Warptalk\warptalk-backend\billing\src\WarpTalk.BillingService.API -S
rg -n "billing_settlement_failed|billing_event_skipped_missing_rate|invoice_overdue_suspend|billing_cycle_closed" D:\Warptalk -S
```

## Production Note

Do not run Phase 3 production migration until the rollback script and latest database backup are both available.
