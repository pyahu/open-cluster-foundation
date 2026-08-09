module "foundation" {
  source = "../../modules/oci-oke-foundation"

  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  region           = var.region

  cluster_name                = var.cluster_name
  kubernetes_version          = var.kubernetes_version
  node_image_id               = var.node_image_id
  ssh_public_key              = var.ssh_public_key
  api_endpoint_public_enabled = var.api_endpoint_public_enabled
  api_endpoint_allowed_cidrs  = var.api_endpoint_allowed_cidrs
  ingress_allowed_cidrs       = var.ingress_allowed_cidrs
  vcn_cidr                    = var.vcn_cidr
  subnet_cidrs                = var.subnet_cidrs
  node_pools                  = var.node_pools

  bastion_enabled       = var.bastion_enabled
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
  tags                  = var.tags
}
