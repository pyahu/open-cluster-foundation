variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string

  validation {
    condition     = startswith(var.tenancy_ocid, "ocid1.tenancy.")
    error_message = "tenancy_ocid must be an OCI tenancy OCID."
  }
}

variable "compartment_ocid" {
  description = "Dedicated compartment OCID for the cluster."
  type        = string

  validation {
    condition     = startswith(var.compartment_ocid, "ocid1.compartment.")
    error_message = "compartment_ocid must be an OCI compartment OCID."
  }
}

variable "region" {
  description = "OCI region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z0-9-]+-[0-9]+$", var.region))
    error_message = "region must be a valid OCI region identifier."
  }
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
  description = "OKE Kubernetes version."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like v1.36.1."
  }
}

variable "node_image_id" {
  description = "OCI image OCID for worker nodes."
  type        = string

  validation {
    condition     = startswith(var.node_image_id, "ocid1.image.")
    error_message = "node_image_id must be an OCI image OCID."
  }
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

  validation {
    condition     = length(var.api_endpoint_allowed_cidrs) > 0 && alltrue([for cidr in var.api_endpoint_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "api_endpoint_allowed_cidrs must contain at least one valid IPv4 CIDR."
  }
}

variable "ingress_allowed_cidrs" {
  description = "CIDRs allowed to reach future public load balancers on TCP 80/443."
  type        = list(string)

  validation {
    condition     = length(var.ingress_allowed_cidrs) > 0 && alltrue([for cidr in var.ingress_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "ingress_allowed_cidrs must contain at least one valid IPv4 CIDR."
  }
}

variable "vcn_cidr" {
  description = "VCN CIDR."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vcn_cidr))
    error_message = "vcn_cidr must be a valid IPv4 CIDR."
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

  validation {
    condition = alltrue([
      for cidr in values(var.subnet_cidrs) : can(cidrnetmask(cidr))
    ])
    error_message = "Every subnet_cidrs value must be a valid IPv4 CIDR."
  }
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
    autoscaling = optional(object({
      min_size = number
      max_size = number
    }))
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

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) : pool.autoscaling == null || (
        pool.autoscaling.min_size >= 1 &&
        pool.autoscaling.max_size >= pool.autoscaling.min_size &&
        pool.size >= pool.autoscaling.min_size &&
        pool.size <= pool.autoscaling.max_size
      )
    ])
    error_message = "Autoscaling bounds must satisfy 1 <= min_size <= size <= max_size."
  }

  validation {
    condition = !contains(keys(var.node_pools), "database") || try(
      var.node_pools.database.labels["open-cluster-foundation.io/workload"] == "database" &&
      contains(
        [for taint in var.node_pools.database.taints : "${taint.key}=${taint.value}:${taint.effect}"],
        "workload.open-cluster-foundation.io/database=true:NoSchedule",
      ),
      false,
    )
    error_message = "The database node pool must use open-cluster-foundation.io/workload=database and workload.open-cluster-foundation.io/database=true:NoSchedule."
  }
}

variable "control_plane_logging_enabled" {
  description = "Whether OCI Logging collects all OKE control-plane service logs."
  type        = bool
  default     = false
}

variable "vcn_flow_logging_enabled" {
  description = "Whether OCI Logging collects VCN flow logs."
  type        = bool
  default     = false
}

variable "log_retention_duration" {
  description = "OCI service-log retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_duration >= 30 && var.log_retention_duration <= 180 && var.log_retention_duration % 30 == 0
    error_message = "log_retention_duration must be a 30-day increment from 30 through 180."
  }
}

variable "bastion_enabled" {
  description = "Whether to create an OCI Bastion targeting the API endpoint subnet as an operator access path to a private endpoint or private nodes."
  type        = bool
  default     = false
}

variable "bastion_allowed_cidrs" {
  description = "CIDRs allowed to open bastion sessions. Defaults to api_endpoint_allowed_cidrs when empty."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.bastion_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "bastion_allowed_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "tags" {
  description = "Freeform tags applied to all OCI resources."
  type        = map(string)
}
