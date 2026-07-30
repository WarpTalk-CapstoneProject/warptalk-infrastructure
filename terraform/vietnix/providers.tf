provider "openstack" {
  auth_url = var.auth_url
  region   = var.region_name

  # Vietnix documents -k for native OpenStack service endpoints. Every
  # invocation is therefore guarded by scripts/verify-vietnix-api-pin.sh.
  insecure = true
}
