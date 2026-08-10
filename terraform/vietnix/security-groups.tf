locals {
  data_tcp_ports = toset([
    "22",
    "5432",
    "6432",
    "9000",
    "9001",
    "6333",
    "6334",
  ])
  data_service_ports = toset([
    "5432",
    "9000",
    "6333",
    "6334",
  ])
  infra_app_ports = toset([
    "22",
    "6379",
    "5672",
    "15672",
    "15692",
    "4317",
    "4318",
    "5341",
    "9090",
    "9093",
    "3001",
  ])
}

resource "openstack_networking_secgroup_v2" "app" {
  name                 = "warptalk-app"
  description          = "Public edge and administrative access for the WarpTalk App VM."
  delete_default_rules = true
}

resource "openstack_networking_secgroup_v2" "data" {
  name                 = "warptalk-data"
  description          = "Private data services reachable only from the WarpTalk App security group."
  delete_default_rules = true
}

resource "openstack_networking_secgroup_v2" "infra" {
  name                 = "warptalk-infra"
  description          = "Private shared infrastructure reachable only from WarpTalk App and Data."
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "app_ssh" {
  for_each = toset(var.admin_cidrs)

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "app_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "app_https_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "app_https_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "app_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.app.id
}

resource "openstack_networking_secgroup_rule_v2" "data_from_app" {
  for_each = local.data_tcp_ports

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.value)
  port_range_max    = tonumber(each.value)
  remote_group_id   = openstack_networking_secgroup_v2.app.id
  security_group_id = openstack_networking_secgroup_v2.data.id
}

resource "openstack_networking_secgroup_rule_v2" "data_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.data.id
}

resource "openstack_networking_secgroup_rule_v2" "data_from_infra" {
  for_each = local.data_service_ports

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.value)
  port_range_max    = tonumber(each.value)
  remote_group_id   = openstack_networking_secgroup_v2.infra.id
  security_group_id = openstack_networking_secgroup_v2.data.id
}

resource "openstack_networking_secgroup_rule_v2" "infra_from_app" {
  for_each = local.infra_app_ports

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = tonumber(each.value)
  port_range_max    = tonumber(each.value)
  remote_group_id   = openstack_networking_secgroup_v2.app.id
  security_group_id = openstack_networking_secgroup_v2.infra.id
}

resource "openstack_networking_secgroup_rule_v2" "infra_egress" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.infra.id
}
