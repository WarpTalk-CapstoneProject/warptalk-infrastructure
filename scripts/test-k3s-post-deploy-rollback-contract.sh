#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
deploy="$script_dir/deploy-k3s-release.sh"

grep -q "previous_revision=" "$deploy"
grep -q "rollback_release()" "$deploy"
grep -q "post_deploy_checks()" "$deploy"
grep -q "if ! post_deploy_checks" "$deploy"
grep -q "accept-k3s-release.sh" "$deploy"
grep -q '"$helm_locked" rollback "$RELEASE_NAME"' "$deploy"
grep -q '"$helm_locked" uninstall "$RELEASE_NAME"' "$deploy"
# The release order (behaviour is pinned by scripts/test-k3s-release-gate.sh; these are the
# static half, so a refactor cannot quietly drop a step).
if grep -v '^[[:space:]]*#' "$deploy" | grep -Fq -- '--atomic'; then
  echo "deploy-k3s-release.sh must not use helm --atomic: a failed upgrade rolls back to a FAILED revision" >&2
  exit 1
fi
grep -Fq 'select(.status == "deployed")' "$deploy"
gate_line="$(grep -n '^if ! run_migration_gate; then' "$deploy" | cut -d: -f1)"
upgrade_line="$(grep -n '"$helm_locked" upgrade --install "$RELEASE_NAME" "$chart_dir" \\$' "$deploy" | tail -n 1 | cut -d: -f1)"
[ -n "$gate_line" ] && [ -n "$upgrade_line" ] && [ "$gate_line" -lt "$upgrade_line" ] || {
  echo "deploy-k3s-release.sh must run the migration gate before helm upgrade" >&2
  exit 1
}
# Every Helm call runs the locked version; a bare `helm` would be whatever the runner has.
if grep -Eq '^[[:space:]]*helm[[:space:]]' "$deploy"; then
  echo "deploy-k3s-release.sh must call Helm through scripts/helm-locked.sh" >&2
  exit 1
fi
# The rollout gate must fail, never be swallowed.
if grep -v '^[[:space:]]*#' "$script_dir/accept-k3s-release.sh" | grep -Eq '\|\| true'; then
  echo "accept-k3s-release.sh must not ignore a failed rollout or check" >&2
  exit 1
fi

echo "k3s post-deploy rollback contract passed"
