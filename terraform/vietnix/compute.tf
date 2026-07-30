locals {
  bootstrap_script_b64 = filebase64("${path.module}/../../scripts/bootstrap-production-host.sh")
}

resource "openstack_blockstorage_volume_v3" "data_durable" {
  count = var.create_compute ? 1 : 0

  name        = "warptalk-data-durable"
  description = "Durable PostgreSQL, MinIO, and Qdrant data."
  size        = var.data_durable_volume_size_gb
  volume_type = var.volume_type

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_blockstorage_volume_v3" "infra_durable" {
  count = var.create_compute ? 1 : 0

  name        = "warptalk-infra-durable"
  description = "Durable Redis, RabbitMQ, and observability data."
  size        = var.infra_durable_volume_size_gb
  volume_type = var.volume_type

  lifecycle {
    prevent_destroy = true
  }
}

resource "openstack_networking_port_v2" "app" {
  count = var.create_compute ? 1 : 0

  name               = "warptalk-app-01"
  network_id         = openstack_networking_network_v2.warptalk.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.app.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.warptalk.id
    ip_address = var.app_private_ip
  }
}

resource "openstack_networking_port_v2" "data" {
  count = var.create_compute ? 1 : 0

  name               = "warptalk-data-01"
  network_id         = openstack_networking_network_v2.warptalk.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.data.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.warptalk.id
    ip_address = var.data_private_ip
  }
}

resource "openstack_networking_port_v2" "infra" {
  count = var.create_compute ? 1 : 0

  name               = "warptalk-infra-01"
  network_id         = openstack_networking_network_v2.warptalk.id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.infra.id]

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.warptalk.id
    ip_address = var.infra_private_ip
  }
}

resource "openstack_compute_instance_v2" "app" {
  count = var.create_compute ? 1 : 0

  name         = "warptalk-app-01"
  flavor_id    = var.app_flavor_id
  key_pair     = var.keypair_name
  config_drive = true
  user_data = templatefile("${path.module}/cloud-init/app.yaml.tftpl", {
    admin_cidr           = var.admin_cidr
    bootstrap_script_b64 = local.bootstrap_script_b64
  })

  network {
    port = openstack_networking_port_v2.app[0].id
  }

  block_device {
    uuid                  = var.image_id
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    volume_size           = var.app_boot_volume_size_gb
    volume_type           = var.volume_type
    delete_on_termination = true
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [openstack_networking_router_interface_v2.warptalk]
}

resource "openstack_compute_instance_v2" "data" {
  count = var.create_compute ? 1 : 0

  name         = "warptalk-data-01"
  flavor_id    = var.data_flavor_id
  key_pair     = var.keypair_name
  config_drive = true
  user_data = templatefile("${path.module}/cloud-init/data.yaml.tftpl", {
    admin_cidr           = var.admin_cidr
    app_private_ip       = var.app_private_ip
    infra_private_ip     = var.infra_private_ip
    bootstrap_script_b64 = local.bootstrap_script_b64
  })

  network {
    port = openstack_networking_port_v2.data[0].id
  }

  block_device {
    uuid                  = var.image_id
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    volume_size           = var.data_boot_volume_size_gb
    volume_type           = var.volume_type
    delete_on_termination = true
  }

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.data_durable[0].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = -1
    delete_on_termination = false
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [openstack_networking_router_interface_v2.warptalk]
}

resource "openstack_compute_instance_v2" "infra" {
  count = var.create_compute ? 1 : 0

  name         = "warptalk-infra-01"
  flavor_id    = var.infra_flavor_id
  key_pair     = var.keypair_name
  config_drive = true
  user_data = templatefile("${path.module}/cloud-init/infra.yaml.tftpl", {
    admin_cidr           = var.admin_cidr
    app_private_ip       = var.app_private_ip
    data_private_ip      = var.data_private_ip
    bootstrap_script_b64 = local.bootstrap_script_b64
  })

  network {
    port = openstack_networking_port_v2.infra[0].id
  }

  block_device {
    uuid                  = var.image_id
    source_type           = "image"
    destination_type      = "volume"
    boot_index            = 0
    volume_size           = var.infra_boot_volume_size_gb
    volume_type           = var.volume_type
    delete_on_termination = true
  }

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.infra_durable[0].id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = -1
    delete_on_termination = false
  }

  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [openstack_networking_router_interface_v2.warptalk]
}

resource "openstack_networking_floatingip_associate_v2" "app" {
  count = var.create_compute ? 1 : 0

  floating_ip = openstack_networking_floatingip_v2.app.address
  port_id     = openstack_networking_port_v2.app[0].id
  fixed_ip    = var.app_private_ip

  depends_on = [openstack_compute_instance_v2.app]
}
