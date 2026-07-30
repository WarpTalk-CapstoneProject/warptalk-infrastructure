variable "auth_url" {
  description = "Vietnix Keystone v3 authentication endpoint."
  type        = string
  default     = "https://api.vietnix.cloud/v3"
}

variable "region_name" {
  description = "OpenStack region exposed by Vietnix."
  type        = string
  default     = "RegionOne"
}

variable "external_network_id" {
  description = "External network used by the WarpTalk router and Floating IP."
  type        = string
  default     = "79cab11a-122d-43a7-9427-3575d9512413"
}

variable "external_network_name" {
  description = "External pool used when allocating the Floating IP."
  type        = string
  default     = "FLOATING_45_115_16_0_24_VLAN102"
}

variable "image_id" {
  description = "Ubuntu 24.04 cloud image ID."
  type        = string
  default     = "b6b2744e-64d1-478d-8452-d1d7f2f55ac1"
}

variable "keypair_name" {
  description = "Vietnix SSH keypair injected by cloud-init."
  type        = string
  default     = "Codex"
}

variable "private_cidr" {
  description = "WarpTalk private network CIDR."
  type        = string
  default     = "10.20.0.0/24"
}

variable "private_gateway_ip" {
  description = "Gateway address for the WarpTalk private subnet."
  type        = string
  default     = "10.20.0.1"
}

variable "app_private_ip" {
  description = "Fixed private IPv4 address of the App VM."
  type        = string
  default     = "10.20.0.200"
}

variable "data_private_ip" {
  description = "Fixed private IPv4 address of the Data VM."
  type        = string
  default     = "10.20.0.20"
}

variable "infra_private_ip" {
  description = "Fixed private IPv4 address of the Infra VM."
  type        = string
  default     = "10.20.0.30"
}

variable "admin_cidr" {
  description = "Single trusted public IPv4 CIDR allowed to SSH to the App VM."
  type        = string

  validation {
    condition = (
      can(cidrhost(var.admin_cidr, 0)) &&
      var.admin_cidr != "0.0.0.0/0"
    )
    error_message = "admin_cidr must be a valid restricted CIDR and cannot be 0.0.0.0/0."
  }
}

variable "create_compute" {
  description = "Create the catalog-compatible App, Data, and Infra VMs."
  type        = bool
  default     = false
}

variable "app_flavor_id" {
  description = "Vietnix 8 vCPU / 16 GiB App flavor."
  type        = string
  default     = "4ba53b56-41e7-4bee-baca-7c9a68ff4844"
}

variable "data_flavor_id" {
  description = "Vietnix 2 vCPU / 8 GiB Data flavor."
  type        = string
  default     = "1dcc625e-78c0-432c-89ca-e53b61934820"
}

variable "infra_flavor_id" {
  description = "Vietnix 2 vCPU / 4 GiB Infra flavor."
  type        = string
  default     = "468c0c15-08bd-4e1d-8564-5053ce12966b"
}

variable "volume_type" {
  description = "Purchased replicated NVMe volume type."
  type        = string
  default     = "nvmer3"
}

variable "app_boot_volume_size_gb" {
  type    = number
  default = 60
}

variable "data_boot_volume_size_gb" {
  type    = number
  default = 20
}

variable "data_durable_volume_size_gb" {
  type    = number
  default = 35
}

variable "infra_boot_volume_size_gb" {
  type    = number
  default = 20
}

variable "infra_durable_volume_size_gb" {
  type    = number
  default = 15
}

check "compute_inputs" {
  assert {
    condition = (
      !var.create_compute ||
      (
        var.app_flavor_id != "" &&
        var.data_flavor_id != "" &&
        var.infra_flavor_id != ""
      )
    )
    error_message = "App, Data, and Infra flavor IDs are required when create_compute is true."
  }
}

check "storage_quota" {
  assert {
    condition = (
      var.app_boot_volume_size_gb +
      var.data_boot_volume_size_gb +
      var.data_durable_volume_size_gb +
      var.infra_boot_volume_size_gb +
      var.infra_durable_volume_size_gb == 150
    )
    error_message = "The three-host layout must allocate exactly the purchased 150 GiB nvmer3 quota."
  }
}
