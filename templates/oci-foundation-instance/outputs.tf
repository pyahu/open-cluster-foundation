output "cluster_id" {
  description = "OKE cluster OCID."
  value       = module.foundation.cluster_id
}

output "node_pool_ids" {
  description = "OKE node pool OCIDs keyed by pool name."
  value       = module.foundation.node_pool_ids
}

output "vcn_id" {
  description = "VCN OCID."
  value       = module.foundation.vcn_id
}

output "nat_gateway_id" {
  description = "NAT Gateway OCID used by private node and pod subnets for outbound internet access."
  value       = module.foundation.nat_gateway_id
}

output "nat_gateway_public_ip" {
  description = "Reserved public IP address used by the NAT Gateway for outbound internet access."
  value       = module.foundation.nat_gateway_public_ip
}

output "gateway_ids" {
  description = "Gateway OCIDs created for the VCN."
  value       = module.foundation.gateway_ids
}

output "route_table_ids" {
  description = "Route table OCIDs created for public and private subnets."
  value       = module.foundation.route_table_ids
}

output "subnet_ids" {
  description = "Subnet OCIDs created for the cluster."
  value       = module.foundation.subnet_ids
}

output "network_security_group_ids" {
  description = "NSG OCIDs created for the cluster."
  value       = module.foundation.network_security_group_ids
}

output "kubeconfig_command" {
  description = "OCI CLI command to create a kubeconfig for this cluster."
  value       = module.foundation.kubeconfig_command
}
