resource "openstack_networking_network_v2" "warptalk" {
  name           = "warptalk-private"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "warptalk" {
  name            = "warptalk-subnet"
  network_id      = openstack_networking_network_v2.warptalk.id
  cidr            = var.private_cidr
  gateway_ip      = var.private_gateway_ip
  ip_version      = 4
  enable_dhcp     = true
  dns_nameservers = ["1.1.1.1", "8.8.8.8"]

  allocation_pool {
    start = "10.20.0.100"
    end   = "10.20.0.250"
  }
}

resource "openstack_networking_router_v2" "warptalk" {
  name                = "warptalk-router"
  admin_state_up      = true
  external_network_id = var.external_network_id
  enable_snat         = true
}

resource "openstack_networking_router_interface_v2" "warptalk" {
  router_id = openstack_networking_router_v2.warptalk.id
  subnet_id = openstack_networking_subnet_v2.warptalk.id
}

resource "openstack_networking_floatingip_v2" "app" {
  pool = var.external_network_name
}
