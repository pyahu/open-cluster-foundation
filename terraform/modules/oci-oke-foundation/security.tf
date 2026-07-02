resource "oci_core_network_security_group" "api_endpoint" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-api"
  freeform_tags  = local.tags
}

resource "oci_core_network_security_group" "load_balancer" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-lb"
  freeform_tags  = local.tags
}

resource "oci_core_network_security_group" "nodes" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-nodes"
  freeform_tags  = local.tags
}

resource "oci_core_network_security_group" "pods" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-nsg-pods"
  freeform_tags  = local.tags
}

resource "oci_core_network_security_group_security_rule" "api_endpoint_ingress" {
  count = length(var.api_endpoint_allowed_cidrs)

  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.api_endpoint_allowed_cidrs[count.index]
  source_type               = "CIDR_BLOCK"
  description               = "Kubernetes API from approved admin CIDR"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "api_endpoint_egress" {
  network_security_group_id = oci_core_network_security_group.api_endpoint.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "API endpoint outbound"
}

resource "oci_core_network_security_group_security_rule" "lb_ingress_http" {
  count = length(var.ingress_allowed_cidrs)

  network_security_group_id = oci_core_network_security_group.load_balancer.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.ingress_allowed_cidrs[count.index]
  source_type               = "CIDR_BLOCK"
  description               = "HTTP from approved ingress CIDR"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_ingress_https" {
  count = length(var.ingress_allowed_cidrs)

  network_security_group_id = oci_core_network_security_group.load_balancer.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.ingress_allowed_cidrs[count.index]
  source_type               = "CIDR_BLOCK"
  description               = "HTTPS from approved ingress CIDR"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_egress_nodeports" {
  network_security_group_id = oci_core_network_security_group.load_balancer.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = var.subnet_cidrs.nodes
  destination_type          = "CIDR_BLOCK"
  description               = "Load balancer to worker NodePorts"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nodes_ingress_kubelet" {
  network_security_group_id = oci_core_network_security_group.nodes.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Kubelet and node management from the VCN"

  tcp_options {
    destination_port_range {
      min = 10250
      max = 10250
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nodes_ingress_nodeports" {
  network_security_group_id = oci_core_network_security_group.nodes.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.subnet_cidrs.load_balancer
  source_type               = "CIDR_BLOCK"
  description               = "NodePort traffic from public load balancer subnet"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nodes_ingress_vcn_tcp" {
  network_security_group_id = oci_core_network_security_group.nodes.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Intra-VCN TCP"

  tcp_options {
    destination_port_range {
      min = 1
      max = 65535
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nodes_ingress_vcn_udp" {
  network_security_group_id = oci_core_network_security_group.nodes.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Intra-VCN UDP"

  udp_options {
    destination_port_range {
      min = 1
      max = 65535
    }
  }
}

resource "oci_core_network_security_group_security_rule" "nodes_egress_all" {
  network_security_group_id = oci_core_network_security_group.nodes.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Worker outbound via NAT or Service Gateway"
}

resource "oci_core_network_security_group_security_rule" "pods_ingress_vcn_tcp" {
  network_security_group_id = oci_core_network_security_group.pods.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Pod TCP from the VCN"

  tcp_options {
    destination_port_range {
      min = 1
      max = 65535
    }
  }
}

resource "oci_core_network_security_group_security_rule" "pods_ingress_vcn_udp" {
  network_security_group_id = oci_core_network_security_group.pods.id
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = var.vcn_cidr
  source_type               = "CIDR_BLOCK"
  description               = "Pod UDP from the VCN"

  udp_options {
    destination_port_range {
      min = 1
      max = 65535
    }
  }
}

resource "oci_core_network_security_group_security_rule" "pods_egress_all" {
  network_security_group_id = oci_core_network_security_group.pods.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Pod outbound via NAT or Service Gateway"
}

