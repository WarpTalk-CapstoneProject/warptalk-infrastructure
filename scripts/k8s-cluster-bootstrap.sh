#!/bin/sh
set -eu

# WarpTalk Multi-Node Upstream Kubernetes (K8s) Cluster Bootstrapper
# Supported for Ubuntu 22.04 / 24.04 on Vietnix Cloud.

INFRA_IP="${INFRA_IP:-10.20.0.30}"
APP_IP="${APP_IP:-100.72.255.18}"
DATA_IP="${DATA_IP:-10.20.0.20}"
K8S_VERSION="${K8S_VERSION:-v1.31}"

echo "============================================================"
echo " WarpTalk Upstream Kubernetes (K8s) Bootstrapper"
echo " Master Node (Infra): $INFRA_IP"
echo " App Worker Node:     $APP_IP"
echo " Data Storage Node:   $DATA_IP"
echo "============================================================"

cat <<'EOF'
# Node Prerequisites Setup Instructions:
# 1. Disable swap:
#    sudo swapoff -a && sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
# 2. Configure kernel modules & sysctl (overlay, br_netfilter)
# 3. Install containerd & enable SystemdCgroup
# 4. Install kubeadm, kubelet, kubectl (v1.31)
EOF
