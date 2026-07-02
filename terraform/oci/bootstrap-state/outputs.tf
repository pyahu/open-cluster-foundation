output "bucket_name" {
  description = "Object Storage bucket used by the Terraform backend."
  value       = oci_objectstorage_bucket.terraform_state.name
}

output "namespace" {
  description = "Object Storage namespace for the tenancy."
  value       = data.oci_objectstorage_namespace.current.namespace
}

output "backend_hcl" {
  description = "Backend config to paste into terraform/oci/foundation/backend.hcl."
  value = join("\n", compact([
    "bucket    = \"${oci_objectstorage_bucket.terraform_state.name}\"",
    "namespace = \"${data.oci_objectstorage_namespace.current.namespace}\"",
    "region    = \"${var.region}\"",
    "key       = \"oci/foundation/terraform.tfstate\"",
    var.oci_config_file_profile == null ? null : "config_file_profile = \"${var.oci_config_file_profile}\"",
    var.oci_auth == null ? null : "auth      = \"${var.oci_auth}\"",
  ]))
}
