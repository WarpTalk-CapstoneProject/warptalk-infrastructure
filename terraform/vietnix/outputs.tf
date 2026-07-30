output "private_network_id" {
  value = openstack_networking_network_v2.warptalk.id
}

output "private_subnet_id" {
  value = openstack_networking_subnet_v2.warptalk.id
}

output "router_id" {
  value = openstack_networking_router_v2.warptalk.id
}

output "app_security_group_id" {
  value = openstack_networking_secgroup_v2.app.id
}

output "data_security_group_id" {
  value = openstack_networking_secgroup_v2.data.id
}

output "infra_security_group_id" {
  value = openstack_networking_secgroup_v2.infra.id
}

output "app_floating_ip" {
  value = openstack_networking_floatingip_v2.app.address
}

output "app_instance_id" {
  value = try(openstack_compute_instance_v2.app[0].id, null)
}

output "data_instance_id" {
  value = try(openstack_compute_instance_v2.data[0].id, null)
}

output "infra_instance_id" {
  value = try(openstack_compute_instance_v2.infra[0].id, null)
}
