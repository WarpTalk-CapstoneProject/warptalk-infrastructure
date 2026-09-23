#!/usr/bin/env bash
# WarpTalk CNI (Calico) and optional MetalLB installer for the kubeadm cluster.
#
# Every fetched manifest is checksum-verified against deploy/k3s/addons.lock.env BEFORE it is
# applied, like the Barman and RabbitMQ operator manifests in install-k3s-addons.sh. Nothing is
# masked with `|| true`: a failed apply stops the script.
#
# MetalLB is OFF by default. In L2 mode it answers ARP for a VIP; the Vietnix VPC (like any cloud
# SDN) only delivers traffic for addresses it assigned to a port, and a Tailscale address is not
# on that network at all, so an L2 VIP would be unreachable. The default ingress path therefore
# does not use MetalLB: the Traefik Service carries the App VM's VPC address as an externalIP
# (deploy/k3s/traefik-values.yaml, TRAEFIK_EXTERNAL_IPS). Enable MetalLB only in BGP mode against
# a router that peers with it, or in L2 mode on a flat L2 network you control.
set -euo pipefail

: "${KUBECONFIG:?KUBECONFIG must name the target cluster explicitly}"
export KUBECONFIG
# Must equal the kubeadm podSubnet (scripts/k8s-cluster-bootstrap.sh) and network.podCidrs in
# deploy/k3s/k8s-app-values.yaml.
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"
# VXLAN, not IP-in-IP: cloud VPC security groups commonly drop IP protocol 4, which would leave
# cross-node pod traffic silently black-holed while same-node traffic worked.
CALICO_ENCAPSULATION="${CALICO_ENCAPSULATION:-VXLAN}"
INSTALL_METALLB="${INSTALL_METALLB:-false}"
METALLB_MODE="${METALLB_MODE:-bgp}"
METALLB_ADDRESSES="${METALLB_ADDRESSES:-}"
METALLB_PEER_ADDRESS="${METALLB_PEER_ADDRESS:-}"
METALLB_PEER_ASN="${METALLB_PEER_ASN:-}"
METALLB_MY_ASN="${METALLB_MY_ASN:-}"

script_dir="$(CDPATH='' cd -- "$(dirname "$0")" && pwd)"
lock_file="$script_dir/../deploy/k3s/addons.lock.env"

fail() {
  echo "k8s-install-cni-metallb: $*" >&2
  exit 1
}

for dependency in kubectl curl; do
  command -v "$dependency" >/dev/null 2>&1 || fail "missing dependency: $dependency"
done
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
  fail "missing dependency: sha256sum or shasum"
test -r "$lock_file" || fail "cannot read add-on lock"
# shellcheck disable=SC1090
. "$lock_file"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/warptalk-cni.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT INT TERM

fetch_verified() {
  # $1 url, $2 expected sha256, $3 output
  curl --fail --location --silent --show-error "$1" -o "$3"
  actual="$(sha256_of "$3")"
  [ "$actual" = "$2" ] || fail "checksum mismatch for $1: expected $2, got $actual"
}

echo "Installing Calico $CALICO_VERSION (Tigera operator), pod CIDR $POD_CIDR"
operator_manifest="$work_dir/tigera-operator.yaml"
fetch_verified \
  "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/tigera-operator.yaml" \
  "$CALICO_OPERATOR_MANIFEST_SHA256" "$operator_manifest"
# Server-side apply: idempotent on re-runs (the old `kubectl create ... || true` hid every error),
# and it avoids the last-applied annotation size limit on Calico's large CRDs.
kubectl apply --server-side --force-conflicts -f "$operator_manifest"
kubectl rollout status deployment/tigera-operator --namespace tigera-operator --timeout=5m
kubectl wait --for=condition=Established crd/installations.operator.tigera.io --timeout=2m

# Our own Installation instead of the upstream custom-resources.yaml, whose IP pool is
# 192.168.0.0/16 regardless of the kubeadm podSubnet.
kubectl apply --server-side -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        cidr: $POD_CIDR
        encapsulation: $CALICO_ENCAPSULATION
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
kubectl wait --for=condition=Available tigerastatus/calico --timeout=10m

if [ "$INSTALL_METALLB" != "true" ]; then
  echo "MetalLB not installed (INSTALL_METALLB=false); ingress uses the Traefik externalIP path."
  exit 0
fi

[ -n "$METALLB_ADDRESSES" ] || fail "METALLB_ADDRESSES is required (e.g. 203.0.113.10/32)"
case "$METALLB_MODE" in
  bgp)
    [ -n "$METALLB_PEER_ADDRESS" ] && [ -n "$METALLB_PEER_ASN" ] && [ -n "$METALLB_MY_ASN" ] ||
      fail "BGP mode needs METALLB_PEER_ADDRESS, METALLB_PEER_ASN and METALLB_MY_ASN"
    ;;
  l2)
    echo "WARNING: MetalLB L2 only works on a flat L2 segment you control; not on a cloud VPC or Tailscale." >&2
    ;;
  *) fail "METALLB_MODE must be bgp or l2" ;;
esac

echo "Installing MetalLB $METALLB_VERSION ($METALLB_MODE mode)"
metallb_manifest="$work_dir/metallb-native.yaml"
fetch_verified \
  "https://raw.githubusercontent.com/metallb/metallb/v${METALLB_VERSION}/config/manifests/metallb-native.yaml" \
  "$METALLB_MANIFEST_SHA256" "$metallb_manifest"
kubectl apply --server-side -f "$metallb_manifest"
kubectl rollout status deployment/controller --namespace metallb-system --timeout=5m
kubectl rollout status daemonset/speaker --namespace metallb-system --timeout=5m
# The IPAddressPool below is validated by MetalLB's admission webhook; applying it before the
# webhook Service has endpoints fails with "connection refused" (which `|| true` used to hide).
kubectl wait --for=jsonpath='{.subsets[0].addresses[0].ip}' \
  endpoints/metallb-webhook-service --namespace metallb-system --timeout=5m

addresses_yaml=""
old_ifs="$IFS"
IFS=','
for address in $METALLB_ADDRESSES; do
  addresses_yaml="$addresses_yaml
    - $address"
done
IFS="$old_ifs"

if [ "$METALLB_MODE" = "bgp" ]; then
  advertisement="apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: warptalk-bgp-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - warptalk-ip-pool
---
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: warptalk-bgp-peer
  namespace: metallb-system
spec:
  myASN: $METALLB_MY_ASN
  peerASN: $METALLB_PEER_ASN
  peerAddress: $METALLB_PEER_ADDRESS"
else
  advertisement="apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: warptalk-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - warptalk-ip-pool"
fi

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: warptalk-ip-pool
  namespace: metallb-system
spec:
  addresses:$addresses_yaml
---
$advertisement
EOF

echo "Calico and MetalLB ($METALLB_MODE) installed."
