#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tf_root="$repo_root/terraform/vietnix"

fail() {
  echo "vietnix terraform contract: FAIL - $*" >&2
  exit 1
}

required_files=(
  versions.tf
  providers.tf
  variables.tf
  network.tf
  security-groups.tf
  compute.tf
  outputs.tf
  terraform.tfvars.example
  cloud-init/app.yaml.tftpl
  cloud-init/data.yaml.tftpl
  cloud-init/infra.yaml.tftpl
)

[[ -x "$repo_root/scripts/verify-vietnix-api-pin.sh" ]] ||
  fail "executable Vietnix API TLS pin verifier is missing"
[[ -x "$repo_root/scripts/run-vietnix-terraform.sh" ]] ||
  fail "guarded Terraform runner is missing"

if rg -Uq 'apt-get install -y[\s\S]{0,300}awscli' \
  "$repo_root/scripts/bootstrap-production-host.sh"; then
  fail "Ubuntu 24.04 host bootstrap must not request the unavailable awscli apt package"
fi
rg -q 'for port in 22 5432 6432 9000 9001 6333 6334' \
  "$repo_root/scripts/bootstrap-production-host.sh" ||
  fail "Data host bootstrap must preserve SSH access from the App jump host"
rg -q 'usermod -aG docker "\$DEPLOY_USER"' \
  "$repo_root/scripts/bootstrap-production-host.sh" ||
  fail "deployment user must receive Docker socket access"
rg -q '"data-root": "/srv/warptalk/docker"' \
  "$repo_root/scripts/bootstrap-production-host.sh" ||
  fail "Data and Infra Docker state must live on the durable volume"
rg -q 'install -d -m 0750 -o root -g docker /opt/warptalk' \
  "$repo_root/scripts/bootstrap-production-host.sh" ||
  fail "deployment user group must be able to traverse /opt/warptalk"
rg -q 'useradd --system.*warptalk' \
  "$repo_root/scripts/bootstrap-production-host.sh" ||
  fail "Data backup service account is missing"

for file in "${required_files[@]}"; do
  [[ -f "$tf_root/$file" ]] || fail "missing $file"
done

rg -q 'source[[:space:]]*=[[:space:]]*"terraform-provider-openstack/openstack"' \
  "$tf_root/versions.tf" || fail "OpenStack provider is not declared"
rg -q 'version[[:space:]]*=[[:space:]]*"3\.4\.0"' \
  "$tf_root/versions.tf" || fail "OpenStack provider must be pinned to 3.4.0"
rg -q 'auth_url[[:space:]]*=[[:space:]]*var\.auth_url' \
  "$tf_root/providers.tf" || fail "provider auth URL must be variable-driven"
rg -q 'insecure[[:space:]]*=[[:space:]]*true' \
  "$tf_root/providers.tf" || fail "documented Vietnix service endpoints require guarded insecure mode"

rg -q 'resource "openstack_networking_network_v2" "warptalk"' \
  "$tf_root/network.tf" || fail "private network is missing"
rg -q 'cidr[[:space:]]*=[[:space:]]*var\.private_cidr' \
  "$tf_root/network.tf" || fail "private CIDR is not variable-driven"
rg -q 'start[[:space:]]*=[[:space:]]*"10\.20\.0\.100"' \
  "$tf_root/network.tf" || fail "DHCP pool must reserve the fixed VM address range"
rg -q 'resource "openstack_networking_router_v2" "warptalk"' \
  "$tf_root/network.tf" || fail "router is missing"
rg -q 'resource "openstack_networking_floatingip_v2" "app"' \
  "$tf_root/network.tf" || fail "App floating IP is missing"

rg -q 'resource "openstack_networking_secgroup_v2" "app"' \
  "$tf_root/security-groups.tf" || fail "App security group is missing"
rg -q 'resource "openstack_networking_secgroup_v2" "data"' \
  "$tf_root/security-groups.tf" || fail "Data security group is missing"
rg -q 'resource "openstack_networking_secgroup_v2" "infra"' \
  "$tf_root/security-groups.tf" || fail "Infra security group is missing"
rg -q 'for_each[[:space:]]*=[[:space:]]*toset\(var\.admin_cidrs\)' \
  "$tf_root/security-groups.tf" || fail "SSH rules are not driven by admin_cidrs"
rg -q 'remote_ip_prefix[[:space:]]*=[[:space:]]*each\.value' \
  "$tf_root/security-groups.tf" || fail "SSH is not restricted to admin_cidrs"
rg -q 'remote_group_id[[:space:]]*=[[:space:]]*openstack_networking_secgroup_v2\.app\.id' \
  "$tf_root/security-groups.tf" || fail "Data ingress is not restricted to the App group"
for internal_port in 22 5432 6432 9000 9001 6333 6334; do
  rg -q "\"$internal_port\"" "$tf_root/security-groups.tf" ||
    fail "Data ingress contract is missing TCP $internal_port"
done
for infra_port in 22 6379 5672 15672 15692 4317 4318 5341 9090 9093 3001; do
  rg -q "\"$infra_port\"" "$tf_root/security-groups.tf" ||
    fail "Infra ingress contract is missing TCP $infra_port"
done

rg -q 'resource "openstack_compute_instance_v2" "app"' \
  "$tf_root/compute.tf" || fail "App VM is missing"
rg -q 'resource "openstack_compute_instance_v2" "data"' \
  "$tf_root/compute.tf" || fail "Data VM is missing"
rg -q 'resource "openstack_compute_instance_v2" "infra"' \
  "$tf_root/compute.tf" || fail "Infra VM is missing"
rg -q 'count[[:space:]]*=[[:space:]]*var\.create_compute[[:space:]]*\?[[:space:]]*1[[:space:]]*:[[:space:]]*0' \
  "$tf_root/compute.tf" || fail "compute creation gate is missing"
rg -q 'delete_on_termination[[:space:]]*=[[:space:]]*false' \
  "$tf_root/compute.tf" || fail "durable Data volume deletion protection is missing"
rg -q 'user_data[[:space:]]*=[[:space:]]*templatefile' \
  "$tf_root/compute.tf" || fail "cloud-init user data is not wired into compute"
[[ "$(rg -c 'ignore_changes[[:space:]]*=[[:space:]]*\[user_data\]' "$tf_root/compute.tf")" -eq 3 ]] ||
  fail "all VMs must ignore post-bootstrap user_data drift"
rg -q 'bootstrap-production-host\.sh' \
  "$tf_root/compute.tf" || fail "canonical host bootstrap is not embedded in cloud-init"
rg -q 'ip_address[[:space:]]*=[[:space:]]*var\.app_private_ip' \
  "$tf_root/compute.tf" || fail "App fixed private IP is missing"
rg -Uq 'variable "app_private_ip"[\s\S]*default[[:space:]]*=[[:space:]]*"10\.20\.0\.200"' \
  "$tf_root/variables.tf" || fail "App fixed IP must be a verified-free address in the managed allocation pool"
rg -q 'ip_address[[:space:]]*=[[:space:]]*var\.data_private_ip' \
  "$tf_root/compute.tf" || fail "Data fixed private IP is missing"
rg -q 'ip_address[[:space:]]*=[[:space:]]*var\.infra_private_ip' \
  "$tf_root/compute.tf" || fail "Infra fixed private IP is missing"
for flavor_id in \
  4ba53b56-41e7-4bee-baca-7c9a68ff4844 \
  1dcc625e-78c0-432c-89ca-e53b61934820 \
  468c0c15-08bd-4e1d-8564-5053ce12966b; do
  rg -q "$flavor_id" "$tf_root/variables.tf" ||
    fail "catalog-compatible flavor $flavor_id is missing"
done
rg -q 'var\.infra_boot_volume_size_gb' "$tf_root/variables.tf" ||
  fail "Infra boot volume is missing from the storage quota check"
rg -q 'var\.infra_durable_volume_size_gb' "$tf_root/variables.tf" ||
  fail "Infra durable volume is missing from the storage quota check"

rg -q 'verify-vietnix-api-pin\.sh' \
  "$repo_root/scripts/run-vietnix-terraform.sh" ||
  fail "Terraform runner does not verify the Vietnix API TLS pin"
rg -q 'security find-generic-password' \
  "$repo_root/scripts/run-vietnix-terraform.sh" ||
  fail "Terraform runner does not load the API secret from Keychain"

if rg -n \
  '(BEGIN (RSA |OPENSSH )?PRIVATE KEY|application_credential_secret[[:space:]]*=[[:space:]]*"[^"]+")' \
  "$tf_root"; then
  fail "credential or private key material is present"
fi

if api_secret="$(
  security find-generic-password \
    -s codex-warptalk-vietnix-api \
    -a project-135846 \
    -w 2>/dev/null
)"; then
  if rg -Fq -- "$api_secret" "$repo_root"; then
    fail "the Keychain API secret is present in the repository"
  fi
fi
unset api_secret

terraform -chdir="$tf_root" fmt -check -recursive >/dev/null ||
  fail "terraform formatting is invalid"

echo "vietnix terraform contract: PASS"
