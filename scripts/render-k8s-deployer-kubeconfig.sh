#!/usr/bin/env bash
# Print a kubeconfig for the warptalk-deployer ServiceAccount (deploy/k3s/cluster/deployer-rbac.yaml),
# to be stored as the GitHub `production` environment secret K8S_KUBECONFIG. Run once, after the
# k8s-bootstrap job has applied the RBAC, with an admin KUBECONFIG:
#
#   K8S_API_SERVER=https://<tailnet-reachable-address>:6443 \
#     scripts/render-k8s-deployer-kubeconfig.sh |
#     gh secret set K8S_KUBECONFIG --env production --repo WarpTalk-CapstoneProject/warptalk-infrastructure
#
# The token never touches disk or a terminal when piped as above.
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG must point at an admin kubeconfig}"
: "${K8S_API_SERVER:?K8S_API_SERVER (the https:// address the release runner reaches over Tailscale) is required}"
export KUBECONFIG
namespace="warptalk-deploy"
secret="warptalk-deployer-token"

case "$K8S_API_SERVER" in
  https://*) ;;
  *) echo "K8S_API_SERVER must be an https:// URL" >&2; exit 1 ;;
esac

secret_json="$(kubectl get secret "$secret" --namespace "$namespace" -o json)"
token="$(printf '%s\n' "$secret_json" | jq -r '.data.token // empty' | base64 -d)"
ca="$(printf '%s\n' "$secret_json" | jq -r '.data["ca.crt"] // empty')"
[ -n "$token" ] && [ -n "$ca" ] || {
  echo "the token Secret has not been populated yet" >&2
  exit 1
}

cat <<KUBECONFIG_EOF
apiVersion: v1
kind: Config
clusters:
  - name: warptalk-production
    cluster:
      server: $K8S_API_SERVER
      certificate-authority-data: $ca
users:
  - name: warptalk-deployer
    user:
      token: $token
contexts:
  - name: warptalk-production
    context:
      cluster: warptalk-production
      user: warptalk-deployer
current-context: warptalk-production
KUBECONFIG_EOF
