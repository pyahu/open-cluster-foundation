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
  tenancy_ocid                = "ocid1.tenancy.oc1..example"
  compartment_ocid            = "ocid1.compartment.oc1..example"
  region                      = "eu-lisbon-1"
  cluster_name                = "example-prod"
  kubernetes_version          = "v1.36.1"
  node_image_id               = "ocid1.image.oc1.eu-lisbon-1.example"
  api_endpoint_public_enabled = false
  api_endpoint_allowed_cidrs  = ["203.0.113.10/32"]
  ingress_allowed_cidrs       = ["0.0.0.0/0"]
  vcn_cidr                    = "10.42.0.0/16"
  subnet_cidrs = {
    api_endpoint  = "10.42.0.0/24"
    load_balancer = "10.42.1.0/24"
    nodes         = "10.42.10.0/24"
    pods          = "10.42.32.0/19"
  }
  node_pools = {
    worker = {
      shape                     = "VM.Standard.E5.Flex"
      size                      = 3
      ocpus                     = 2
      memory_in_gbs             = 24
      boot_volume_size_in_gbs   = 100
      max_pods_per_node         = 31
      availability_domain_count = 3
      autoscaling = {
        min_size = 3
        max_size = 9
      }
    }
  }
  bastion_enabled               = true
  control_plane_logging_enabled = true
  vcn_flow_logging_enabled      = true
  tags                          = {}
}

run "production_contract" {
  command = plan

  assert {
    condition     = output.kubeconfig.endpoint == "PRIVATE_ENDPOINT"
    error_message = "New production configurations must support a private endpoint."
  }

  assert {
    condition     = output.cluster_autoscaler_node_groups.worker.min_size == 3 && output.cluster_autoscaler_node_groups.worker.max_size == 9
    error_message = "Cluster Autoscaler boundaries were not preserved."
  }

  assert {
    condition     = length(oci_logging_log.control_plane) == 1 && length(oci_logging_log.vcn_flow) == 1 && length(oci_core_capture_filter.vcn_flow) == 1
    error_message = "Requested OCI service logs were not planned."
  }
}

run "existing_cluster_compatibility" {
  command = plan

  variables {
    api_endpoint_public_enabled   = true
    bastion_enabled               = false
    control_plane_logging_enabled = false
    vcn_flow_logging_enabled      = false
    node_pools = {
      worker = {
        shape                     = "VM.Standard.A1.Flex"
        size                      = 9
        ocpus                     = 2
        memory_in_gbs             = 12
        boot_volume_size_in_gbs   = 100
        max_pods_per_node         = 31
        availability_domain_count = 3
      }
    }
  }

  assert {
    condition     = output.kubeconfig.endpoint == "PUBLIC_ENDPOINT"
    error_message = "Existing public endpoint mode was not preserved."
  }

  assert {
    condition     = length(oci_logging_log_group.foundation) == 0 && length(oci_logging_log.control_plane) == 0 && length(oci_logging_log.vcn_flow) == 0 && length(oci_core_capture_filter.vcn_flow) == 0
    error_message = "Compatibility defaults unexpectedly enabled OCI Logging."
  }

  assert {
    condition     = length(output.cluster_autoscaler_node_groups) == 0
    error_message = "Existing fixed-size node pools unexpectedly received autoscaling bounds."
  }
}

run "reject_subnet_outside_vcn" {
  command = plan

  variables {
    subnet_cidrs = {
      api_endpoint  = "10.42.0.0/24"
      load_balancer = "10.42.1.0/24"
      nodes         = "10.43.10.0/24"
      pods          = "10.42.32.0/19"
    }
  }

  expect_failures = [oci_core_vcn.this]
}

run "reject_overlapping_subnets" {
  command = plan

  variables {
    subnet_cidrs = {
      api_endpoint  = "10.42.0.0/24"
      load_balancer = "10.42.0.128/25"
      nodes         = "10.42.10.0/24"
      pods          = "10.42.32.0/19"
    }
  }

  expect_failures = [oci_core_vcn.this]
}

run "reject_invalid_autoscaling_bounds" {
  command = plan

  variables {
    node_pools = {
      worker = {
        shape                     = "VM.Standard.E5.Flex"
        size                      = 3
        ocpus                     = 2
        memory_in_gbs             = 24
        boot_volume_size_in_gbs   = 100
        max_pods_per_node         = 31
        availability_domain_count = 3
        autoscaling = {
          min_size = 4
          max_size = 9
        }
      }
    }
  }

  expect_failures = [var.node_pools]
}
