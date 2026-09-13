resource "oci_bastion_bastion" "this" {
  count = var.bastion_enabled ? 1 : 0

  bastion_type     = "standard"
  compartment_id   = var.compartment_ocid
  target_subnet_id = oci_core_subnet.api_endpoint.id

  name = "${replace(var.cluster_name, "-", "")}bastion"

  client_cidr_block_allow_list = local.bastion_allowed_cidrs
  max_session_ttl_in_seconds   = 10800
}
