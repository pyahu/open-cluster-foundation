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

output "bastion_id" {
  description = "OCI Bastion OCID, or null when bastion_enabled is false."
  value       = module.foundation.bastion_id
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

output "logging" {
  description = "OCI Logging resources created for the foundation."
  value       = module.foundation.logging
}

output "cluster_autoscaler_node_groups" {
  description = "Validated node-pool boundaries for OCI Cluster Autoscaler configuration."
  value       = module.foundation.cluster_autoscaler_node_groups
}

output "cluster_autoscaler_nodes" {
  description = "Value for the OCI Cluster Autoscaler managed add-on nodes configuration."
  value       = module.foundation.cluster_autoscaler_nodes
}

output "kubeconfig" {
  description = "Structured inputs used by scripts/oci-instance.sh kubeconfig."
  value = merge(module.foundation.kubeconfig, {
    profile = var.oci_config_file_profile
  })
}

output "provider_contract" {
  description = "Provider-neutral Open Cluster Foundation contract for composition and conformance tests."
  value       = module.foundation.provider_contract
}

output "kubeconfig_command" {
  description = "Legacy OCI CLI command retained for compatibility. Automation should use the structured kubeconfig output."
  value       = module.foundation.kubeconfig_command
}
