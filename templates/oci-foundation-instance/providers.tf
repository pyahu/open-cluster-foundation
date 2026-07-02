provider "oci" {
  region              = var.region
  auth                = var.oci_auth
  config_file_profile = var.oci_config_file_profile
}
