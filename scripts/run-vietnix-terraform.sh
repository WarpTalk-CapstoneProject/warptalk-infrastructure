#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_root="$repo_root/terraform/vietnix"
readonly keychain_service="codex-warptalk-vietnix-api"
readonly keychain_account="project-135846"
readonly application_credential_id="b9ee1dd2226045f99d4feab8fccdf30c"

usage() {
  echo "Usage: $0 {fmt|init|validate|plan|apply|output} [terraform arguments...]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
command_name="$1"
shift

case "$command_name" in
  fmt | init | validate | plan | apply | output) ;;
  *) usage ;;
esac

"$repo_root/scripts/verify-vietnix-api-pin.sh"

export OS_AUTH_URL="https://api.vietnix.cloud/v3"
export OS_AUTH_TYPE="v3applicationcredential"
export OS_APPLICATION_CREDENTIAL_ID="$application_credential_id"
OS_APPLICATION_CREDENTIAL_SECRET="$(
  security find-generic-password \
    -s "$keychain_service" \
    -a "$keychain_account" \
    -w
)"
export OS_APPLICATION_CREDENTIAL_SECRET
export OS_REGION_NAME="RegionOne"

trap 'unset OS_APPLICATION_CREDENTIAL_SECRET' EXIT
terraform -chdir="$tf_root" "$command_name" "$@"
