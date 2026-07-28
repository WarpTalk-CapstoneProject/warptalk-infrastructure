#!/bin/sh
set -eu

NAMESPACE="${K3S_NAMESPACE:-warptalk}"
SECRET_NAME="${K3S_RUNTIME_SECRET_NAME:-warptalk-runtime}"
script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
contract_file="$script_dir/../deploy/k3s/runtime-secret-contract.json"

fail() {
  echo "K3s runtime secret contract: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "missing dependency: jq"
test -r "$contract_file" || fail "cannot read runtime secret contract"

if [ -n "${K3S_RUNTIME_SECRET_FILE:-}" ]; then
  test -r "$K3S_RUNTIME_SECRET_FILE" ||
    fail "cannot read K3S_RUNTIME_SECRET_FILE"
  secret_json="$(cat "$K3S_RUNTIME_SECRET_FILE")"
else
  command -v kubectl >/dev/null 2>&1 || fail "missing dependency: kubectl"
  secret_json="$(kubectl get secret "$SECRET_NAME" --namespace "$NAMESPACE" -o json)" ||
    fail "cannot read $NAMESPACE/$SECRET_NAME"
fi

printf '%s\n' "$secret_json" | jq -e --slurpfile contract "$contract_file" '
  $contract[0] as $contract |
  .data as $data |
  all($contract.requiredNonEmptyKeys[]; (($data[.] // "") | length) > 0) and
  (($contract.requiredPresentKeys - ($data | keys)) | length == 0) and
  all($contract.minimumDecodedLength | to_entries[];
    (($data[.key] | @base64d | length) >= .value)) and
  all($contract.pgbouncerConnectionKeys[];
    ($data[.] | @base64d | contains($contract.pgbouncerHost))) and
  ($data | to_entries | all(.[]; (.value | @base64d |
    contains("CHANGE_ME") | not)))
' >/dev/null ||
  fail "missing, empty, weak, placeholder, or non-PgBouncer runtime value"

echo "K3s runtime secret contract: PASS ($NAMESPACE/$SECRET_NAME)"
