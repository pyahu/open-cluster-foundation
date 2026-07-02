resource "oci_core_vcn" "this" {
  compartment_id = var.compartment_ocid
  display_name   = var.cluster_name
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = replace(substr(var.cluster_name, 0, 15), "-", "")
  freeform_tags  = local.tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-igw"
  enabled        = true
  freeform_tags  = local.tags
}

resource "oci_core_public_ip" "nat" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.cluster_name}-nat-ip"
  lifetime       = "RESERVED"
  freeform_tags  = local.tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-natgw"
  public_ip_id   = oci_core_public_ip.nat.id
  freeform_tags  = local.tags
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "this" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-sgw"
  freeform_tags  = local.tags

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-rt-public"
  freeform_tags  = local.tags

  route_rules {
    network_entity_id = oci_core_internet_gateway.this.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    description       = "Internet egress and public ingress via IGW"
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-rt-private"
  freeform_tags  = local.tags

  route_rules {
    network_entity_id = oci_core_nat_gateway.this.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    description       = "Outbound internet via NAT Gateway"
  }

  route_rules {
    network_entity_id = oci_core_service_gateway.this.id
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    description       = "OCI services via Service Gateway"
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-sl-public"
  freeform_tags  = local.tags

  dynamic "ingress_security_rules" {
    for_each = var.ingress_allowed_cidrs

    content {
      protocol = "6"
      source   = ingress_security_rules.value

      tcp_options {
        min = 80
        max = 80
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.ingress_allowed_cidrs

    content {
      protocol = "6"
      source   = ingress_security_rules.value

      tcp_options {
        min = 443
        max = 443
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.api_endpoint_allowed_cidrs

    content {
      protocol = "6"
      source   = ingress_security_rules.value

      tcp_options {
        min = 6443
        max = 6443
      }
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.cluster_name}-sl-private"
  freeform_tags  = local.tags

  ingress_security_rules {
    protocol = "6"
    source   = var.vcn_cidr

    tcp_options {
      min = 1
      max = 65535
    }
  }

  ingress_security_rules {
    protocol = "17"
    source   = var.vcn_cidr

    udp_options {
      min = 1
      max = 65535
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = var.vcn_cidr
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "api_endpoint" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.cluster_name}-subnet-api"
  cidr_block                 = var.subnet_cidrs.api_endpoint
  route_table_id             = var.api_endpoint_public_enabled ? oci_core_route_table.public.id : oci_core_route_table.private.id
  security_list_ids          = var.api_endpoint_public_enabled ? [oci_core_security_list.public.id] : [oci_core_security_list.private.id]
  dns_label                  = "api"
  prohibit_public_ip_on_vnic = !var.api_endpoint_public_enabled
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "load_balancer" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.cluster_name}-subnet-lb"
  cidr_block                 = var.subnet_cidrs.load_balancer
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  dns_label                  = "lb"
  prohibit_public_ip_on_vnic = false
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "nodes" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.cluster_name}-subnet-nodes"
  cidr_block                 = var.subnet_cidrs.nodes
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  dns_label                  = "nodes"
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
}

resource "oci_core_subnet" "pods" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "${var.cluster_name}-subnet-pods"
  cidr_block                 = var.subnet_cidrs.pods
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.private.id]
  dns_label                  = "pods"
  prohibit_public_ip_on_vnic = true
  freeform_tags              = local.tags
}
