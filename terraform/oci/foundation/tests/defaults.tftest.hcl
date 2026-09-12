mock_provider "oci" {
  mock_data "oci_identity_availability_domains" {
    defaults = {
      availability_domains = [
        {
          name = "AD-1"
        },
        {
          name = "AD-2"
        },
        {
          name = "AD-3"
        },
      ]
    }
  }

  mock_data "oci_core_services" {
    defaults = {
      services = [
        {
          cidr_block = "all-lis-services-in-oracle-services-network"
          id         = "ocid1.service.oc1.eu-lisbon-1.example"
        },
      ]
    }
  }
}

variables {
  tenancy_ocid               = "ocid1.tenancy.oc1..example"
  compartment_ocid           = "ocid1.compartment.oc1..example"
  region                     = "eu-lisbon-1"
  cluster_name               = "example-prod"
  kubernetes_version         = "v1.36.1"
  node_image_id              = "ocid1.image.oc1.eu-lisbon-1.example"
  api_endpoint_allowed_cidrs = ["203.0.113.10/32"]
}

run "recommended_defaults" {
  command = apply

  assert {
    condition     = output.kubeconfig.endpoint == "PRIVATE_ENDPOINT"
    error_message = "The foundation entrypoint must default to a private API endpoint."
  }

  assert {
    condition     = output.bastion_id != null
    error_message = "The foundation entrypoint must provide a private access path by default."
  }

  assert {
    condition     = output.logging.log_group_id != null && output.logging.control_plane_log_id != null && output.logging.vcn_flow_log_id != null
    error_message = "The foundation entrypoint must enable OCI service logging by default."
  }

  assert {
    condition     = output.cluster_autoscaler_node_groups.worker.min_size == 3 && output.cluster_autoscaler_node_groups.worker.max_size == 9
    error_message = "The foundation entrypoint must publish reasonable worker autoscaling boundaries."
  }
}
