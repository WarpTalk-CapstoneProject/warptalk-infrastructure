terraform {
  required_version = ">= 1.6.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.4.0"
    }
  }

  backend "local" {
    path = "../.local-state/vietnix/terraform.tfstate"
  }
}
