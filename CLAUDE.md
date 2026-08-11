# WarpTalk infrastructure Claude instructions

## Production deployment

Use `.github/workflows/release.yml` (`immutable-release`) as the only normal
production release path. Supply full backend, web, AI, and infrastructure commit
SHAs and a never-reused immutable release tag. Do not weaken its build, SBOM,
Trivy, or Cosign gates.

The `production` Environment no longer requires a human reviewer. On 2026-08-08 the
owner replaced that gate with a **5-minute `wait_timer`**: a successful build now
deploys on its own, and the window exists to cancel a run dispatched with the wrong
SHA or tag. Do not re-add `required_reviewers` without being asked — its absence is
a decision, not drift.

`branch_policy` stays: only `main` may deploy to production. And `environment:
production` must stay on the deploy job whatever else changes — the job's secrets
are scoped to that environment, so removing the line breaks the deploy rather than
skipping a gate.

Never perform a normal release from a local/direct SSH session, manually invoke
the VM deployment scripts, or ask the user for an SSH key. GitHub Actions owns
the host transport via repository/environment secrets and Tailscale. Direct SSH
is only for explicitly requested emergency recovery or narrow read-only
diagnostics when workflow evidence is insufficient.

When the user says **"kiểm tra log lỗi của prod"**, or makes an equivalent
request, follow `health-inspector/AGENT-RUNBOOK.md` and run the deployed health
inspector on App, Data, and Infra. A one-host, local-only, dashboard-only, or
health-endpoint-only check is not a whole-production log inspection.
