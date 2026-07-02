variable "compartment_ocid" {
  description = "Dedicated compartment OCID where the state bucket will be created."
  type        = string
}

variable "region" {
  description = "OCI region, for example sa-saopaulo-1."
  type        = string
}

variable "name_prefix" {
  description = "Lowercase prefix used when bucket_name is not set."
  type        = string
  default     = "pyahu-oci"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name_prefix))
    error_message = "name_prefix must be 2-31 chars, lowercase alphanumeric or hyphen, and start with a letter."
  }
}

variable "bucket_name" {
  description = "Optional explicit bucket name. Leave null to generate one from name_prefix."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-zA-Z0-9._-]{1,256}$", var.bucket_name))
    error_message = "bucket_name must be a valid OCI Object Storage bucket name."
  }
}

variable "oci_auth" {
  description = "Optional OCI provider auth mode. Leave null for the default API key config."
  type        = string
  default     = null

  validation {
    condition = (
      var.oci_auth == null ||
      contains(["APIKey", "SecurityToken", "InstancePrincipal", "ResourcePrincipal"], var.oci_auth)
    )
    error_message = "oci_auth must be APIKey, SecurityToken, InstancePrincipal or ResourcePrincipal."
  }
}

variable "oci_config_file_profile" {
  description = "OCI config profile name, for example PYAHU_TERRAFORM."
  type        = string
  default     = null
}

variable "tags" {
  description = "Freeform tags applied to bootstrap resources."
  type        = map(string)
  default = {
    project    = "pyahu"
    managed_by = "terraform"
  }
}

