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
}

variable "oci_config_file_profile" {
  description = "OCI config profile name."
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "OKE cluster name and naming prefix for OCI resources."
  type        = string
}

variable "kubernetes_version" {
  description = "OKE Kubernetes version."
  type        = string
}

variable "node_image_id" {
  description = "OCI image OCID for worker nodes, compatible with the selected node shape."
  type        = string
}

variable "ssh_public_key" {
  description = "Optional SSH public key injected into worker nodes."
  type        = string
  default     = null
}

variable "api_endpoint_public_enabled" {
  description = "Whether the Kubernetes API endpoint receives a public IP."
  type        = bool
  default     = true
}

variable "api_endpoint_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API endpoint on TCP 6443."
  type        = list(string)
}

variable "ingress_allowed_cidrs" {
  description = "CIDRs allowed to reach future public load balancers on TCP 80/443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "vcn_cidr" {
  description = "VCN CIDR."
  type        = string
  default     = "10.42.0.0/16"
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
    managed_by = "terraform"
  }
}
