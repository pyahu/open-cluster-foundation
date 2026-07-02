data "oci_identity_availability_domains" "available" {
  compartment_id = var.tenancy_ocid
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  vcn_id             = oci_core_vcn.this.id
  type               = "ENHANCED_CLUSTER"
  freeform_tags      = local.tags

  endpoint_config {
    is_public_ip_enabled = var.api_endpoint_public_enabled
    nsg_ids              = [oci_core_network_security_group.api_endpoint.id]
    subnet_id            = oci_core_subnet.api_endpoint.id
  }

  cluster_pod_network_options {
    cni_type = "OCI_VCN_IP_NATIVE"
  }

  options {
    service_lb_subnet_ids = [oci_core_subnet.load_balancer.id]
  }
}

resource "oci_containerengine_node_pool" "this" {
  for_each = var.node_pools

  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = var.kubernetes_version
  name               = "${var.cluster_name}-${each.key}"
  node_shape         = each.value.shape
  freeform_tags      = local.tags

  node_shape_config {
    memory_in_gbs = each.value.memory_in_gbs
    ocpus         = each.value.ocpus
  }

  node_config_details {
    nsg_ids = [oci_core_network_security_group.nodes.id]
    size    = each.value.size

    dynamic "placement_configs" {
      for_each = slice(
        data.oci_identity_availability_domains.available.availability_domains,
        0,
        min(
          length(data.oci_identity_availability_domains.available.availability_domains),
          each.value.availability_domain_count,
        ),
      )

      content {
        availability_domain = placement_configs.value.name
        subnet_id           = oci_core_subnet.nodes.id
      }
    }

    node_pool_pod_network_option_details {
      cni_type          = "OCI_VCN_IP_NATIVE"
      max_pods_per_node = each.value.max_pods_per_node
      pod_nsg_ids       = [oci_core_network_security_group.pods.id]
      pod_subnet_ids    = [oci_core_subnet.pods.id]
    }
  }

  node_source_details {
    boot_volume_size_in_gbs = each.value.boot_volume_size_in_gbs
    image_id                = var.node_image_id
    source_type             = "IMAGE"
  }

  node_metadata = local.node_pool_metadata[each.key]

  dynamic "initial_node_labels" {
    for_each = merge(
      {
        "open-cluster-foundation.io/node-pool" = each.key
      },
      each.value.labels,
    )

    content {
      key   = initial_node_labels.key
      value = initial_node_labels.value
    }
  }

  node_pool_cycling_details {
    is_node_cycling_enabled = true
    maximum_surge           = "1"
    maximum_unavailable     = "0"
  }
}

resource "oci_containerengine_addon" "metrics_server" {
  count = var.metrics_server_addon_enabled ? 1 : 0

  addon_name                       = "KubernetesMetricsServer"
  cluster_id                       = oci_containerengine_cluster.this.id
  remove_addon_resources_on_delete = true
}
