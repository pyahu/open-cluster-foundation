variable "tenancy_ocid" {
  type = string
}

variable "compartment_ocid" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "node_image_id" {
  type = string
}

variable "api_endpoint_allowed_cidrs" {
  type = list(string)
}

variable "ingress_allowed_cidrs" {
  type = list(string)
}

variable "vcn_cidr" {
  type = string
}

variable "subnet_cidrs" {
  type = object({
    api_endpoint  = string
    load_balancer = string
    nodes         = string
    pods          = string
  })
}
