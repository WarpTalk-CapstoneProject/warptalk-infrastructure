#!/usr/bin/env bash
# WarpTalk upstream Kubernetes (kubeadm) bootstrap for the three Vietnix VMs.
#
# One-time host setup, run ON THE CONTROL-PLANE (Infra) VM by an operator. It is not a release
# path: releases go through .github/workflows/release.yml (deploy_target=k8s).
#
#   MODE=render (default)  write the kubeadm config to $KUBEADM_CONFIG and print the commands
#   MODE=init              additionally run `kubeadm init` with it
#
# Every node address is a PARAMETER, and all three must be on ONE network (NODE_CIDR). The previous
# version mixed the App VM's Tailscale address (100.72.255.18) with VPC addresses (10.20.0.x), so
# kubelets would have advertised addresses on two different networks. The live cluster
# (2026-09-23) uses the tailnet for all three (100.70.83.108 / 100.72.255.18 / 100.122.196.85,
# NODE_CIDR=100.64.0.0/10), which is also how the release runner reaches the API server; a VPC
# build uses NODE_CIDR=10.20.0.0/24.
set -euo pipefail

MODE="${MODE:-render}"
NODE_CIDR="${NODE_CIDR:-100.64.0.0/10}"
: "${INFRA_IP:?INFRA_IP (control-plane VPC address) is required}"
: "${APP_IP:?APP_IP (App VM VPC address) is required}"
: "${DATA_IP:?DATA_IP (Data VM VPC address) is required}"
K8S_VERSION="${K8S_VERSION:-v1.31.0}"
# Must equal network.podCidrs in deploy/k3s/k8s-app-values.yaml (the gateway trusts
# X-Forwarded-For from it) and the Calico IP pool (scripts/k8s-install-cni-metallb.sh). The live
# cluster runs Calico's 192.168.0.0/16.
POD_CIDR="${POD_CIDR:-192.168.0.0/16}"
SERVICE_CIDR="${SERVICE_CIDR:-10.96.0.0/12}"
# Optional: the tailnet address or MagicDNS name the release runner uses to reach the API server
# (K8S_KUBECONFIG's `server`). Added to the API server certificate SANs.
API_TAILNET_SAN="${API_TAILNET_SAN:-}"
KUBEADM_CONFIG="${KUBEADM_CONFIG:-/etc/warptalk/kubeadm-config.yaml}"

fail() {
  echo "k8s-cluster-bootstrap: $*" >&2
  exit 1
}

ip_to_int() {
  local IFS=.
  # shellcheck disable=SC2086
  set -- $1
  [ "$#" -eq 4 ] || return 1
  echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 ))
}

in_cidr() {
  local address="$1" cidr="$2" network bits mask
  network="${cidr%/*}"
  bits="${cidr#*/}"
  mask=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
  [ $(( $(ip_to_int "$address") & mask )) -eq $(( $(ip_to_int "$network") & mask )) ]
}

for pair in "INFRA_IP=$INFRA_IP" "APP_IP=$APP_IP" "DATA_IP=$DATA_IP"; do
  name="${pair%%=*}"
  address="${pair#*=}"
  ip_to_int "$address" >/dev/null || fail "$name=$address is not an IPv4 address"
  in_cidr "$address" "$NODE_CIDR" ||
    fail "$name=$address is outside NODE_CIDR $NODE_CIDR; all three nodes must use one network"
done
[ "$INFRA_IP" != "$APP_IP" ] && [ "$APP_IP" != "$DATA_IP" ] && [ "$INFRA_IP" != "$DATA_IP" ] ||
  fail "INFRA_IP, APP_IP and DATA_IP must be three different nodes"
if in_cidr "${POD_CIDR%/*}" "$NODE_CIDR"; then
  fail "POD_CIDR $POD_CIDR overlaps NODE_CIDR $NODE_CIDR"
fi

cert_sans="    - $INFRA_IP"
if [ -n "$API_TAILNET_SAN" ]; then
  cert_sans="$cert_sans
    - $API_TAILNET_SAN"
fi

install -d -m 0755 "$(dirname "$KUBEADM_CONFIG")"
umask 077
cat >"$KUBEADM_CONFIG" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $INFRA_IP
nodeRegistration:
  kubeletExtraArgs:
    - name: node-ip
      value: $INFRA_IP
  taints:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: $K8S_VERSION
controlPlaneEndpoint: $INFRA_IP:6443
networking:
  podSubnet: $POD_CIDR
  serviceSubnet: $SERVICE_CIDR
apiServer:
  certSANs:
$cert_sans
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
# Kubelet serving certificates signed by the cluster CA (approved below), so metrics-server can
# verify kubelets instead of running with --kubelet-insecure-tls.
serverTLSBootstrap: true
# Reserved for the OS and the kubelet, so a busy node evicts pods before the kernel OOM-kills
# system daemons. deploy/k3s/README.md "Capacity plan" budgets against what is left.
systemReserved:
  cpu: 200m
  memory: 512Mi
kubeReserved:
  cpu: 200m
  memory: 512Mi
evictionHard:
  memory.available: 200Mi
  nodefs.available: 10%
EOF

cat <<EOF
Wrote $KUBEADM_CONFIG (pod CIDR $POD_CIDR, API endpoint $INFRA_IP:6443).

Node prerequisites on all three VMs (swap off, overlay + br_netfilter, containerd with
SystemdCgroup, kubeadm/kubelet/kubectl $K8S_VERSION) must already be in place.

1. Control plane (this VM):   kubeadm init --config $KUBEADM_CONFIG
2. Join each worker with its OWN VPC address as the kubelet node-ip:
     App  ($APP_IP):  kubeadm join $INFRA_IP:6443 ... then set KUBELET_EXTRA_ARGS=--node-ip=$APP_IP
     Data ($DATA_IP): kubeadm join $INFRA_IP:6443 ... then set KUBELET_EXTRA_ARGS=--node-ip=$DATA_IP
3. Approve the kubelet serving certificates (repeat after each kubelet cert rotation):
     kubectl get csr -o name | xargs -r kubectl certificate approve
4. CNI:  POD_CIDR=$POD_CIDR scripts/k8s-install-cni-metallb.sh
5. Everything after that (node labels and taints, add-ons, deployer RBAC) is the k8s-bootstrap
   job in release.yml: dispatch with deploy_target=k8s and k8s_bootstrap=true.
EOF

if [ "$MODE" = "init" ]; then
  command -v kubeadm >/dev/null 2>&1 || fail "kubeadm is not installed"
  kubeadm init --config "$KUBEADM_CONFIG"
fi
