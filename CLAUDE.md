# WarpTalk infrastructure Claude instructions

## Production deployment

Use `.github/workflows/release.yml` (`immutable-release`) as the only normal
production release path. Supply full backend, web, AI, and infrastructure commit
SHAs and a never-reused immutable release tag. Do not weaken its build, SBOM,
Trivy, Cosign, or GitHub Environment approval gates.

Never perform a normal release from a local/direct SSH session, manually invoke
the VM deployment scripts, or ask the user for an SSH key. GitHub Actions owns
the host transport via repository/environment secrets and Tailscale. Direct SSH
is only for explicitly requested emergency recovery or narrow read-only
diagnostics when workflow evidence is insufficient.

When the user says **"kiểm tra log lỗi của prod"**, or makes an equivalent
request, follow `health-inspector/AGENT-RUNBOOK.md` and run the deployed health
inspector on App, Data, and Infra. A one-host, local-only, dashboard-only, or
health-endpoint-only check is not a whole-production log inspection.
