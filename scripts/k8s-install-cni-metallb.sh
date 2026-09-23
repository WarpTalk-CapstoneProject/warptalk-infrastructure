#!/bin/sh
set -eu

# WarpTalk CNI & LoadBalancer Installer for Upstream Kubernetes
# Installs Calico CNI v3.28.0 + MetalLB v0.14.8 on the Master Node.

echo "Installing Calico CNI (Tigera Operator)..."
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml || true
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml || true

echo "Installing MetalLB LoadBalancer..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml || true

echo "Configuring MetalLB IPAddressPool & L2Advertisement..."
cat <<'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: warptalk-ip-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.20.0.100-10.20.0.120
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: warptalk-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - warptalk-ip-pool
EOF

echo "MetalLB and Calico CNI setup completed."
