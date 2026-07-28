#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
deploy="$script_dir/deploy-k3s-release.sh"

grep -q "previous_revision=" "$deploy"
grep -q "rollback_release()" "$deploy"
grep -q "post_deploy_checks()" "$deploy"
grep -q "if ! post_deploy_checks" "$deploy"
grep -q "accept-k3s-release.sh" "$deploy"
grep -q 'helm rollback "$RELEASE_NAME"' "$deploy"
grep -q 'helm uninstall "$RELEASE_NAME"' "$deploy"

echo "k3s post-deploy rollback contract passed"
