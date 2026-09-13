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

output "logging" {
  description = "OCI Logging resources created for the foundation."
  value = {
    log_group_id          = local.logging_enabled ? oci_logging_log_group.foundation[0].id : null
    control_plane_log_id  = var.control_plane_logging_enabled ? oci_logging_log.control_plane[0].id : null
    vcn_flow_log_id       = var.vcn_flow_logging_enabled ? oci_logging_log.vcn_flow[0].id : null
    vcn_capture_filter_id = var.vcn_flow_logging_enabled ? oci_core_capture_filter.vcn_flow[0].id : null
  }
}

output "cluster_autoscaler_node_groups" {
  description = "Validated node-pool boundaries for the OCI Cluster Autoscaler nodes configuration."
  value = {
    for name, pool in var.node_pools : name => {
      node_pool_id = oci_containerengine_node_pool.this[name].id
      min_size     = pool.autoscaling.min_size
      max_size     = pool.autoscaling.max_size
    } if pool.autoscaling != null
  }
}

output "cluster_autoscaler_nodes" {
  description = "Value for the OCI Cluster Autoscaler managed add-on nodes configuration."
  value = join(",", [
    for name, pool in var.node_pools :
    "${pool.autoscaling.min_size}:${pool.autoscaling.max_size}:${oci_containerengine_node_pool.this[name].id}"
    if pool.autoscaling != null
  ])
}

output "kubeconfig" {
  description = "Structured inputs for OCI CLI kubeconfig generation."
  value = {
    cluster_id   = oci_containerengine_cluster.this.id
    cluster_name = var.cluster_name
    endpoint     = local.kube_endpoint_mode
    region       = var.region
  }
}

output "provider_contract" {
  description = "Provider-neutral Open Cluster Foundation contract for composition and conformance tests."
  value = {
    schema_version = "1.0.0"
    provider = {
      name             = "oci"
      terraform_source = "oracle/oci"
    }
    cluster = {
      id                          = oci_containerengine_cluster.this.id
      name                        = var.cluster_name
      kubernetes_version          = var.kubernetes_version
      api_endpoint_public_enabled = var.api_endpoint_public_enabled
    }
    network = {
      id   = oci_core_vcn.this.id
      cidr = var.vcn_cidr
      subnet_ids = {
        api_endpoint  = oci_core_subnet.api_endpoint.id
        load_balancer = oci_core_subnet.load_balancer.id
        nodes         = oci_core_subnet.nodes.id
        pods          = oci_core_subnet.pods.id
      }
    }
    node_pools = {
      for name, pool in var.node_pools : name => {
        id          = oci_containerengine_node_pool.this[name].id
        size        = pool.size
        labels      = pool.labels
        taints      = pool.taints
        autoscaling = pool.autoscaling
      }
    }
    capabilities = {
      bastion               = var.bastion_enabled
      cluster_autoscaler    = length([for pool in values(var.node_pools) : pool if pool.autoscaling != null]) > 0
      control_plane_logging = var.control_plane_logging_enabled
      network_flow_logging  = var.vcn_flow_logging_enabled
    }
    kubeconfig = {
      cluster_id   = oci_containerengine_cluster.this.id
      cluster_name = var.cluster_name
      endpoint     = local.kube_endpoint_mode
      region       = var.region
    }
  }
}

output "kubeconfig_command" {
  description = "Legacy OCI CLI command retained for compatibility. Automation should use the structured kubeconfig output."
  value = join(" ", [
    "oci ce cluster create-kubeconfig",
    "--cluster-id ${oci_containerengine_cluster.this.id}",
    "--file ${local.kubeconfig_path}",
    "--region ${var.region}",
    "--token-version 2.0.0",
    "--kube-endpoint ${local.kube_endpoint_mode}",
  ])
}
