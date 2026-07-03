output "cluster_id" {
  description = "OKE cluster OCID."
  value       = oci_containerengine_cluster.this.id
}

output "node_pool_ids" {
  description = "OKE node pool OCIDs keyed by pool name."
  value       = { for name, pool in oci_containerengine_node_pool.this : name => pool.id }
}

output "vcn_id" {
  description = "VCN OCID."
  value       = oci_core_vcn.this.id
}

output "nat_gateway_id" {
  description = "NAT Gateway OCID used by private node and pod subnets for outbound internet access."
  value       = oci_core_nat_gateway.this.id
}

output "nat_gateway_public_ip" {
  description = "Reserved public IP address used by the NAT Gateway for outbound internet access."
  value       = oci_core_public_ip.nat.ip_address
}

output "gateway_ids" {
  description = "Gateway OCIDs created for the VCN."
  value = {
    internet_gateway = oci_core_internet_gateway.this.id
    nat_gateway      = oci_core_nat_gateway.this.id
    service_gateway  = oci_core_service_gateway.this.id
  }
}

output "bastion_id" {
  description = "OCI Bastion OCID, or null when bastion_enabled is false."
  value       = var.bastion_enabled ? oci_bastion_bastion.this[0].id : null
}

output "route_table_ids" {
  description = "Route table OCIDs created for public and private subnets."
  value = {
    public  = oci_core_route_table.public.id
    private = oci_core_route_table.private.id
  }
}

output "subnet_ids" {
  description = "Subnet OCIDs."
  value = {
    api_endpoint  = oci_core_subnet.api_endpoint.id
    load_balancer = oci_core_subnet.load_balancer.id
    nodes         = oci_core_subnet.nodes.id
    pods          = oci_core_subnet.pods.id
  }
}

output "network_security_group_ids" {
  description = "Network Security Group OCIDs."
  value = {
    api_endpoint  = oci_core_network_security_group.api_endpoint.id
    load_balancer = oci_core_network_security_group.load_balancer.id
    nodes         = oci_core_network_security_group.nodes.id
    pods          = oci_core_network_security_group.pods.id
  }
}

output "kubeconfig_command" {
  description = "OCI CLI command to create a kubeconfig for this cluster."
  value = join(" ", [
    "oci ce cluster create-kubeconfig",
    "--cluster-id ${oci_containerengine_cluster.this.id}",
    "--file ${local.kubeconfig_path}",
    "--region ${var.region}",
    "--token-version 2.0.0",
    "--kube-endpoint ${local.kube_endpoint_mode}",
  ])
}
