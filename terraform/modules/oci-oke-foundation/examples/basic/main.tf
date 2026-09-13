terraform {
  required_version = ">= 1.12.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.9"
    }
  }
}

module "foundation" {
  source = "../.."

  tenancy_ocid                  = var.tenancy_ocid
  compartment_ocid              = var.compartment_ocid
  region                        = var.region
  cluster_name                  = var.cluster_name
  kubernetes_version            = var.kubernetes_version
  node_image_id                 = var.node_image_id
  api_endpoint_allowed_cidrs    = var.api_endpoint_allowed_cidrs
  ingress_allowed_cidrs         = var.ingress_allowed_cidrs
  vcn_cidr                      = var.vcn_cidr
  subnet_cidrs                  = var.subnet_cidrs
  api_endpoint_public_enabled   = false
  bastion_enabled               = true
  control_plane_logging_enabled = true
  vcn_flow_logging_enabled      = true
  node_pools = {
    worker = {
      shape                     = "VM.Standard.E5.Flex"
      size                      = 3
      ocpus                     = 2
      memory_in_gbs             = 24
      boot_volume_size_in_gbs   = 100
      max_pods_per_node         = 31
      availability_domain_count = 3
      labels = {
        "node-pool" = "worker"
      }
      autoscaling = {
        min_size = 3
        max_size = 9
      }
    }
  }
  tags = {
    managed_by = "terraform"
  }
}
