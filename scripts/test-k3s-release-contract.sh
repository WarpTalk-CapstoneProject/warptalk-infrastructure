#!/bin/sh
set -eu

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
infra_root="$(CDPATH='' cd -- "$script_dir/.." && pwd)"
matrix="$infra_root/deploy/production/image-matrix.json"
provider_values="$infra_root/deploy/k3s/provider-values.contract.yaml"

manifest="$(mktemp "${TMPDIR:-/tmp}/warptalk-release-contract.XXXXXX")"
incomplete_manifest="$(mktemp "${TMPDIR:-/tmp}/warptalk-release-incomplete.XXXXXX")"
invalid_cost_values="$(mktemp "${TMPDIR:-/tmp}/warptalk-cost-invalid.XXXXXX")"
trap 'rm -f "$manifest" "$incomplete_manifest" "$invalid_cost_values"' EXIT INT TERM

jq '{
  schemaVersion: 1,
  tag: "contract01",
  images: [
    .images[] | {
      service,
      ref: ("ghcr.io/warptalk/" + .name + ":contract01"),
      digest: ("sha256:" + ("1" * 64))
    }
  ]
}' "$matrix" >"$manifest"

RELEASE_MANIFEST="$manifest" \
K3S_VALUES_FILE="$provider_values" \
K3S_SECRET_STORE_NAME=contract-secret-store \
K3S_STORAGE_CLASS=replicated-nvme \
K3S_TLS_SECRET_NAME=contract-warptalk-tls \
OFFLINE_RENDER_ONLY=true \
  "$script_dir/deploy-k3s-release.sh"

jq '.images |= .[1:]' "$manifest" >"$incomplete_manifest"
if RELEASE_MANIFEST="$incomplete_manifest" \
  K3S_VALUES_FILE="$provider_values" \
  K3S_SECRET_STORE_NAME=contract-secret-store \
  K3S_STORAGE_CLASS=replicated-nvme \
  K3S_TLS_SECRET_NAME=contract-warptalk-tls \
  OFFLINE_RENDER_ONLY=true \
  "$script_dir/deploy-k3s-release.sh" >/dev/null 2>&1; then
  echo "incomplete release manifest was accepted" >&2
  exit 1
fi

sed 's/"100"/"0"/g' "$provider_values" >"$invalid_cost_values"
if RELEASE_MANIFEST="$manifest" \
  K3S_VALUES_FILE="$invalid_cost_values" \
  K3S_SECRET_STORE_NAME=contract-secret-store \
  K3S_STORAGE_CLASS=replicated-nvme \
  K3S_TLS_SECRET_NAME=contract-warptalk-tls \
  OFFLINE_RENDER_ONLY=true \
  "$script_dir/deploy-k3s-release.sh" >/dev/null 2>&1; then
  echo "zero production cost budgets were accepted" >&2
  exit 1
fi

echo "K3s immutable release contract tests: PASS"
