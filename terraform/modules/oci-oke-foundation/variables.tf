variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
}

variable "compartment_ocid" {
  description = "Dedicated compartment OCID for the cluster."
  type        = string
}

variable "region" {
  description = "OCI region."
  type        = string
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
  description = "OCI image OCID for worker nodes."
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
}

variable "vcn_cidr" {
  description = "VCN CIDR."
  type        = string
}

variable "subnet_cidrs" {
  description = "Subnet CIDRs for the foundation."
  type = object({
    api_endpoint  = string
    load_balancer = string
    nodes         = string
    pods          = string
  })
}

variable "node_pools" {
  description = "OKE managed node pools keyed by pool name. Labels and taints are applied by kubelet at node registration, so they survive scaling and node cycling. Avoid labels under node-role.kubernetes.io: kubelet self-labeling is rejected for that prefix by the NodeRestriction admission plugin."
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

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) : alltrue([
        for taint in pool.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], taint.effect)
      ])
    ])
    error_message = "Taint effect must be NoSchedule, PreferNoSchedule or NoExecute."
  }
}

variable "bastion_enabled" {
  description = "Whether to create an OCI Bastion (managed, no cost) targeting the API endpoint subnet. Required when api_endpoint_public_enabled is false; useful for SSH sessions to private nodes in any mode."
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
}
