# OCI OKE Foundation Module

Reusable implementation module for the public OCI foundation entrypoint at
`terraform/oci/foundation`.

This module creates the network, gateways, OKE cluster and private managed node
pools. Users should normally run the provider entrypoint or a private instance
template rather than this module directly.

## Network Contract

- Dedicated VCN.
- Internet Gateway for public load balancers.
- NAT Gateway with a reserved public IP for outbound internet access from
  private node and pod subnets.
- Service Gateway for private access to OCI services.
- Public route table for load balancers and, when enabled, the Kubernetes API
  endpoint.
- Private route table for nodes and pods.
- Private worker node subnet.
- Private VCN-native pod subnet.

The module exposes `nat_gateway_id`, `nat_gateway_public_ip`, `gateway_ids`,
`route_table_ids`, `subnet_ids` and `network_security_group_ids` so callers can
validate the foundation and compose follow-up automation.

## Node Pools

`node_pools` is a map keyed by pool name. Each pool controls shape, size,
OCPU/RAM, boot volume size, pod density and initial Kubernetes labels.

The OCI Terraform provider supports initial node labels but does not currently
expose Kubernetes taints for OKE managed node pools. Apply taints after
kubeconfig generation when a pool must be reserved for database or other
dedicated workloads.
