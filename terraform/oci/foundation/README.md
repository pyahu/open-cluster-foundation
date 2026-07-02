# OCI Foundation

Provisions a Kubernetes foundation on Oracle Cloud Infrastructure.

OCI is the first implemented cloud provider in Open Cluster Foundation. The
same repository is intended to grow provider modules for Magalu Cloud,
DigitalOcean and others, while sharing the same provider-agnostic Kubernetes
base layer.

This module creates:

- Dedicated VCN.
- Public subnet for load balancers.
- Kubernetes API subnet with public access restricted by CIDR.
- Private subnets for nodes and pods.
- Internet Gateway for public load balancers.
- NAT Gateway with a reserved public IP for outbound internet access from
  private nodes and pods.
- Service Gateway for private access to OCI services.
- OKE Enhanced Cluster.
- One or more private node pools with OCI VCN-Native Pod Networking.

Envoy Gateway, Prometheus, Grafana, Loki, cert-manager and other add-ons are
installed by separate Kubernetes modules.

## Network Layout

The foundation uses native OCI gateways and keeps worker capacity private by
default.

| Subnet | Public IPs | Route table | Purpose |
| --- | --- | --- | --- |
| API endpoint | Optional | Public or private | Kubernetes API endpoint. |
| Load balancer | Yes | Public | Future public Kubernetes load balancers. |
| Nodes | No | Private | OKE worker nodes. |
| Pods | No | Private | VCN-native pod networking. |

The public route table sends `0.0.0.0/0` to the Internet Gateway. The private
route table sends `0.0.0.0/0` to the NAT Gateway and OCI service CIDRs to the
Service Gateway. The NAT Gateway uses a reserved public IP, giving private
nodes and pods stable outbound internet egress without assigning public IPs to
worker node VNICs.

## 1. Prerequisites

- Terraform `>= 1.12`.
- Authenticated OCI CLI.
- `kubectl`.
- A dedicated compartment for the cluster.
- The remote state bucket created by `terraform/oci/bootstrap-state`.

## 2. IAM Policies

For a first foundation in an isolated compartment, start with:

```text
Allow group ocf-cluster-admins to read compartments in tenancy
Allow group ocf-cluster-admins to inspect tenancies in tenancy
Allow group ocf-cluster-admins to manage cluster-family in compartment <compartment-name>
Allow group ocf-cluster-admins to manage virtual-network-family in compartment <compartment-name>
Allow group ocf-cluster-admins to manage instance-family in compartment <compartment-name>
Allow group ocf-cluster-admins to manage volume-family in compartment <compartment-name>
Allow group ocf-cluster-admins to manage load-balancers in compartment <compartment-name>
Allow group ocf-cluster-admins to manage object-family in compartment <compartment-name>
```

For production, refine these policies by group, compartment and automation
pipeline.

## 3. Discover OCI Values

Tenancy:

```sh
oci iam tenancy get --tenancy-id "$(oci iam region-subscription list \
  --query 'data[0]."tenancy-id"' --raw-output)"
```

Compartments:

```sh
oci iam compartment list \
  --compartment-id <tenancy_ocid> \
  --all \
  --query 'data[].{name:name,id:id}'
```

OKE Kubernetes versions available in a region:

```sh
oci ce cluster-options get \
  --cluster-option-id all \
  --region sa-saopaulo-1
```

Worker image compatible with the node shape:

```sh
oci compute image list \
  --compartment-id <compartment_ocid> \
  --shape VM.Standard.A1.Flex \
  --operating-system "Oracle Linux" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --all \
  --query 'data[0].{displayName:"display-name",id:id}'
```

Your public IP for Kubernetes API allowlisting:

```sh
curl -fsSL https://ifconfig.me
```

Use `<ip>/32` in `api_endpoint_allowed_cidrs`.

## 4. Configure Remote State

Copy the bootstrap output:

```sh
cd terraform/oci/bootstrap-state
terraform output -raw backend_hcl
```

Create `terraform/oci/foundation/backend.hcl` with that content.

Example:

```hcl
bucket              = "pyahu-oci-tfstate-a1b2c3"
namespace           = "mytenancynamespace"
region              = "sa-saopaulo-1"
key                 = "oci/foundation/terraform.tfstate"
config_file_profile = "PYAHU_TERRAFORM"
```

## 5. Configure Variables

```sh
cd terraform/oci/foundation
cp terraform.tfvars.example terraform.tfvars
```

Edit:

- `tenancy_ocid`
- `compartment_ocid`
- `region`
- `kubernetes_version`
- `node_image_id`
- `api_endpoint_allowed_cidrs`
- `node_pools`

The example starts with two node pools:

```text
worker   = 3 x VM.Standard.E5.Flex, 2 OCPU, 24 GB RAM
database = 2 x VM.Standard.E5.Flex, 2 OCPU, 24 GB RAM
```

Labels and taints declared in `node_pools` are registered by kubelet at node
startup through cloud-init, so nodes created by scaling or node cycling come up
already tainted. To reserve a pool for database workloads, declare the taint in
`terraform.tfvars`:

```hcl
taints = [
  {
    key    = "workload.open-cluster-foundation.io/database"
    value  = "true"
    effect = "NoSchedule"
  },
]
```

For nodes created before taints were configured, and to add the
`node-role.kubernetes.io/postgres` label (which kubelet cannot self-apply), use
`mise run k8s:nodes:taint-database -- --yes`.

## 6. Provision

```sh
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

## 7. Generate Kubeconfig

After apply:

```sh
terraform output -raw kubeconfig_command
```

Run the returned command. Then:

```sh
export KUBECONFIG="$HOME/.kube/pyahu-oci-foundation.yaml"
kubectl get nodes
kubectl get pods -A
```

## 8. Verify Network Egress

The Terraform output exposes the NAT Gateway, gateways, route tables and
subnets so operators can validate the network before migrating workloads:

```sh
terraform output nat_gateway_id
terraform output -raw nat_gateway_public_ip
terraform output gateway_ids
terraform output route_table_ids
terraform output subnet_ids
```

Use the OCI CLI to inspect the NAT Gateway and the private route table:

```sh
oci network nat-gateway get \
  --nat-gateway-id "$(terraform output -raw nat_gateway_id)"

oci network route-table get \
  --rt-id "$(terraform output -json route_table_ids | jq -r .private)"
```

The private route table must contain a default route to the NAT Gateway. The
nodes and pods subnets must use that private route table. Share
`nat_gateway_public_ip` with external systems only when they require firewall
allowlisting for outbound traffic from workloads.

## Current Decisions

- OKE instead of k3s: lower operational burden for a public foundation.
- Enhanced Cluster: the current path for new OKE clusters.
- NAT Gateway with reserved public IP by default: private nodes and pods can
  reach the internet for image pulls, package downloads and external APIs
  without receiving public IPs, while operators keep a stable egress IP for
  external firewall allowlists.
- Private nodes: workloads do not receive public IPs.
- Public Kubernetes API endpoint for initial simplicity, restricted by CIDR.
- VCN-Native Pod Networking: pods receive VCN IPs, which improves OCI integration.
- Multiple node pools: callers can create workload-specific pools without
  duplicating the network and cluster code.
- Add-ons stay outside this stack: the foundation should remain small and predictable.

## Official References

- Terraform OCI backend: <https://developer.hashicorp.com/terraform/language/backend/oci>
- Terraform style guide: <https://developer.hashicorp.com/terraform/language/style>
- Terraform standard module structure: <https://developer.hashicorp.com/terraform/language/modules/develop/structure>
- OCI Terraform provider: <https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/>
- `oci_containerengine_cluster`: <https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/containerengine_cluster.html>
- `oci_containerengine_node_pool`: <https://docs.oracle.com/en-us/iaas/tools/terraform-provider-oci/latest/docs/r/containerengine_node_pool.html>
