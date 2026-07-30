#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
contract="$script_dir/../deploy/k3s/runtime-secret-contract.json"
checker="$script_dir/check-k3s-runtime-secret.sh"
fixture="$(mktemp "${TMPDIR:-/tmp}/warptalk-runtime-secret.XXXXXX")"
invalid="$(mktemp "${TMPDIR:-/tmp}/warptalk-runtime-secret-invalid.XXXXXX")"
trap 'rm -f "$fixture" "$invalid"' EXIT INT TERM

jq -n --slurpfile contract "$contract" '
  $contract[0] as $contract |
  (($contract.requiredNonEmptyKeys + $contract.requiredPresentKeys) | unique) as $keys |
  {
    apiVersion: "v1",
    kind: "Secret",
    metadata: {name: "warptalk-runtime", namespace: "warptalk"},
    data: (
      reduce $keys[] as $key ({};
        .[$key] = ("contract-value" | @base64)
      )
      | .JWT_PREVIOUS_SECRETS = ("" | @base64)
      | .JWT_SECRET = (("j" * 64) | @base64)
      | .GRPC_INTERNAL_SECRET = (("g" * 64) | @base64)
      | .WORKSPACE_STORAGE_MASTER_KEY = (("s" * 32) | @base64)
      | reduce $contract.pgbouncerConnectionKeys[] as $key (.;
          .[$key] = (
            ("Host=" + $contract.pgbouncerHost + ";Port=5432;Database=contract")
            | @base64
          )
        )
    )
  }
' >"$fixture"

K3S_RUNTIME_SECRET_FILE="$fixture" "$checker" >/dev/null

jq 'del(.data.AUTH_CONNECTION_STRING)' "$fixture" >"$invalid"
if K3S_RUNTIME_SECRET_FILE="$invalid" "$checker" >/dev/null 2>&1; then
  echo "runtime secret contract accepted a missing key" >&2
  exit 1
fi

jq '.data.STRIPE_SECRET_KEY = ("CHANGE_ME" | @base64)' "$fixture" >"$invalid"
if K3S_RUNTIME_SECRET_FILE="$invalid" "$checker" >/dev/null 2>&1; then
  echo "runtime secret contract accepted a placeholder" >&2
  exit 1
fi

echo "K3s runtime secret contract tests: PASS"
