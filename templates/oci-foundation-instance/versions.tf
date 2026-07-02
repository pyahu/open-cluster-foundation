terraform {
  required_version = ">= 1.12.0"

  backend "oci" {}

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.9"
    }
  }
}
