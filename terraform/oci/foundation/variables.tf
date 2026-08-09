variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
}

variable "compartment_ocid" {
  description = "Dedicated compartment OCID for the cluster."
  type        = string
}

variable "region" {
  description = "OCI region, for example sa-saopaulo-1."
  type        = string
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

variable "cluster_name" {
  description = "OKE cluster name and naming prefix for OCI resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.cluster_name))
    error_message = "cluster_name must be 3-41 chars, lowercase alphanumeric or hyphen, and start with a letter."
  }
}

variable "kubernetes_version" {
  description = "OKE Kubernetes version, for example v1.33.1. Check supported versions per region before apply."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like v1.33.1."
  }
}

variable "node_image_id" {
  description = "OCI image OCID for worker nodes, compatible with the selected node shape."
  type        = string
}

variable "ssh_public_key" {
  description = "Optional SSH public key injected into worker nodes. Nodes are private; prefer OCI Bastion for access."
  type        = string
  default     = null
}

variable "api_endpoint_public_enabled" {
  description = "Whether the Kubernetes API endpoint receives a public IP. Keep true only with tight api_endpoint_allowed_cidrs."
  type        = bool
  default     = true
}

variable "api_endpoint_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint on TCP 6443."
  type        = list(string)

  validation {
    condition     = length(var.api_endpoint_allowed_cidrs) > 0 && alltrue([for cidr in var.api_endpoint_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "api_endpoint_allowed_cidrs must contain at least one valid CIDR."
  }
}

variable "ingress_allowed_cidrs" {
  description = "CIDRs allowed to reach future public load balancers on TCP 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.ingress_allowed_cidrs) > 0 && alltrue([for cidr in var.ingress_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "ingress_allowed_cidrs must contain at least one valid CIDR."
  }
}

variable "vcn_cidr" {
  description = "VCN CIDR."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vcn_cidr))
    error_message = "vcn_cidr must be a valid CIDR."
  }
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs for the foundation."
  type = object({
    api_endpoint  = string
    load_balancer = string
    nodes         = string
    pods          = string
  })
  default = {
    api_endpoint  = "10.42.0.0/24"
    load_balancer = "10.42.1.0/24"
    nodes         = "10.42.10.0/24"
    pods          = "10.42.32.0/19"
  }

  validation {
    condition = alltrue([
      for cidr in values(var.subnet_cidrs) : can(cidrnetmask(cidr))
    ])
    error_message = "Every subnet_cidrs value must be a valid CIDR."
  }
}

variable "node_pools" {
  description = "OKE managed node pools keyed by pool name. Labels and taints are registered by kubelet at node startup, so they survive scaling and node cycling."
  type = map(object({
    shape                     = string
    size                      = number
    ocpus                     = number
    memory_in_gbs             = number
    boot_volume_size_in_gbs   = number
    max_pods_per_node         = number
    availability_domain_count = number
    labels                    = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
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
    }
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) : (
        pool.size >= 1 &&
        pool.ocpus >= 1 &&
        pool.memory_in_gbs >= 6 &&
        pool.boot_volume_size_in_gbs >= 50 &&
        pool.max_pods_per_node >= 8 &&
        pool.availability_domain_count >= 1
      )
    ])
    error_message = "node_pools values are below the supported minimums."
  }
}

variable "bastion_enabled" {
  description = "Whether to create an OCI Bastion (managed, no cost) targeting the API endpoint subnet. Required when api_endpoint_public_enabled is false."
  type        = bool
  default     = false
}

variable "bastion_allowed_cidrs" {
  description = "CIDRs allowed to open bastion sessions. Defaults to api_endpoint_allowed_cidrs when empty."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Freeform tags applied to all OCI resources."
  type        = map(string)
  default = {
    project    = "pyahu"
    managed_by = "terraform"
  }
}
