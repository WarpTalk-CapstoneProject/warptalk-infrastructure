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

# The production path: the k8s release job deploys deploy/k3s/k8s-app-values.yaml with runtime
# secrets from GitHub (no ExternalSecret, no secret store) and image refs from the manifest.
RELEASE_MANIFEST="$manifest" \
K3S_VALUES_FILE="$infra_root/deploy/k3s/k8s-app-values.yaml" \
K3S_SECRET_SOURCE=github \
K3S_STORAGE_CLASS=local-path \
K3S_TLS_SECRET_NAME=warptalk-tls \
OFFLINE_RENDER_ONLY=true \
  "$script_dir/deploy-k3s-release.sh"

# The same values with an ExternalSecret switched back on must be refused on the GitHub path.
external_values="$(mktemp "${TMPDIR:-/tmp}/warptalk-external-secret.XXXXXX")"
trap 'rm -f "$manifest" "$incomplete_manifest" "$invalid_cost_values" "$external_values"' EXIT INT TERM
sed 's/^    enabled: false$/    enabled: true/' "$infra_root/deploy/k3s/k8s-app-values.yaml" >"$external_values"
if RELEASE_MANIFEST="$manifest" \
  K3S_VALUES_FILE="$external_values" \
  K3S_SECRET_SOURCE=github \
  K3S_STORAGE_CLASS=local-path \
  K3S_TLS_SECRET_NAME=warptalk-tls \
  OFFLINE_RENDER_ONLY=true \
  "$script_dir/deploy-k3s-release.sh" >/dev/null 2>&1; then
  echo "an ExternalSecret was accepted on the GitHub secret path" >&2
  exit 1
fi

# The online path must refuse to run against an implicit ~/.kube/config.
if env -u KUBECONFIG RELEASE_MANIFEST="$manifest" \
  K3S_VALUES_FILE="$infra_root/deploy/k3s/k8s-app-values.yaml" \
  K3S_SECRET_SOURCE=github \
  K3S_STORAGE_CLASS=local-path \
  K3S_TLS_SECRET_NAME=warptalk-tls \
  K3S_DOMAIN=app.warptalk.io.vn \
  "$script_dir/deploy-k3s-release.sh" >/dev/null 2>&1; then
  echo "the release deploy ran without an explicit KUBECONFIG" >&2
  exit 1
fi
for script in deploy-k3s-data.sh deploy-k3s-release.sh accept-k3s-release.sh install-k3s-addons.sh; do
  grep -Fq 'KUBECONFIG must name the target cluster explicitly' "$script_dir/$script" || {
    echo "$script must require an explicit KUBECONFIG" >&2
    exit 1
  }
  if grep -Fq 'HOME/.kube/config' "$script_dir/$script"; then
    echo "$script falls back to the operator's ~/.kube/config" >&2
    exit 1
  fi
done

echo "K3s immutable release contract tests: PASS"
