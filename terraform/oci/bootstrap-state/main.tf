data "oci_objectstorage_namespace" "current" {}

resource "random_id" "bucket_suffix" {
  byte_length = 3
}

locals {
  bucket_name = coalesce(
    var.bucket_name,
    "${var.name_prefix}-tfstate-${random_id.bucket_suffix.hex}",
  )

  tags = merge(var.tags, {
    blueprint = "oci-bootstrap-state"
  })
}

resource "oci_objectstorage_bucket" "terraform_state" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.current.namespace
  name           = local.bucket_name
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  versioning     = "Enabled"
  freeform_tags  = local.tags
}
