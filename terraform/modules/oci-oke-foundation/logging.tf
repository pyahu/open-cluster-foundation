resource "oci_logging_log_group" "foundation" {
  count = local.logging_enabled ? 1 : 0

  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-logs"
  description    = "Open Cluster Foundation OCI service logs"
  freeform_tags  = local.tags
}

resource "oci_core_capture_filter" "vcn_flow" {
  count = var.vcn_flow_logging_enabled ? 1 : 0

  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-vcn-flow"
  filter_type    = "FLOWLOG"
  freeform_tags  = local.tags

  flow_log_capture_filter_rules {
    flow_log_type = "ALL"
    is_enabled    = true
    priority      = 10
    protocol      = "all"
    rule_action   = "INCLUDE"
    sampling_rate = 1
  }
}

resource "oci_logging_log" "control_plane" {
  count = var.control_plane_logging_enabled ? 1 : 0

  display_name       = "${var.cluster_name}-control-plane"
  log_group_id       = oci_logging_log_group.foundation[0].id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.log_retention_duration
  freeform_tags      = local.tags

  configuration {
    compartment_id = var.compartment_ocid

    source {
      category    = "all-service-logs"
      resource    = oci_containerengine_cluster.this.id
      service     = "oke-k8s-cp-prod"
      source_type = "OCISERVICE"
    }
  }
}

resource "oci_logging_log" "vcn_flow" {
  count = var.vcn_flow_logging_enabled ? 1 : 0

  display_name       = "${var.cluster_name}-vcn-flow"
  log_group_id       = oci_logging_log_group.foundation[0].id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.log_retention_duration
  freeform_tags      = local.tags

  configuration {
    compartment_id = var.compartment_ocid

    source {
      category    = "vcn"
      resource    = oci_core_vcn.this.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
      parameters = {
        capture_filter = oci_core_capture_filter.vcn_flow[0].id
        include_subnet = "true"
        include_vcn    = "true"
      }
    }
  }
}
