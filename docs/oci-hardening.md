# OCI foundation hardening

The OCI foundation entrypoints use private control-plane access, OCI Bastion,
OKE control-plane logging, VCN flow logging and 30-day log retention as the
defaults for new configurations. The reusable implementation module keeps the
older public-endpoint and logging defaults so existing callers are not changed
merely by updating the module source.

| Setting | New foundation entrypoint | Reusable module compatibility default |
| --- | --- | --- |
| Kubernetes API | Private | Public |
| OCI Bastion | Enabled | Disabled |
| OKE control-plane logs | Enabled | Disabled |
| VCN flow logs | Enabled | Disabled |
| Log retention | 30 days | 30 days when enabled |

OCI Logging and Bastion can incur tenancy-specific costs or limits. Review the
current OCI pricing and service limits before applying a production plan.

## Existing public endpoint migration

An existing cluster whose configuration omitted
`api_endpoint_public_enabled` must first preserve its current behavior
explicitly:

```hcl
api_endpoint_public_enabled   = true
bastion_enabled               = false
control_plane_logging_enabled = false
vcn_flow_logging_enabled      = false
```

Run a saved plan and confirm that it contains no endpoint replacement or
endpoint access change. This is the compatibility checkpoint. Do not migrate
the endpoint in the same change that upgrades the module.

Prepare and test a private access path through FastConnect, Site-to-Site VPN,
an operator inside the VCN, or OCI Bastion. With Bastion, create a
port-forwarding session to the API endpoint private IP on TCP 6443. Preserve
the API hostname as the TLS server name if the local tunnel changes the
kubeconfig server address to `https://127.0.0.1:<local-port>`.

After the independent access test succeeds, set:

```hcl
api_endpoint_public_enabled = false
bastion_enabled             = true
```

Inspect the saved plan, apply it during a maintenance window, generate a
separate kubeconfig and verify `/readyz` plus node connectivity. Keep the old
kubeconfig until the new path is proven. To roll back, restore
`api_endpoint_public_enabled = true` with the original tight
`api_endpoint_allowed_cidrs` and apply a reviewed plan.

Oracle documents private OKE endpoints and Bastion in its
[network configuration](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengnetworkconfig.htm)
and [Bastion](https://docs.oracle.com/en-us/iaas/Content/Bastion/home.htm)
guides.

## Service logs

`control_plane_logging_enabled` creates one OCI service log using the
`all-service-logs` OKE category. It includes the Kubernetes API server,
controller manager, scheduler and OCI cloud controller manager streams.
`vcn_flow_logging_enabled` creates a capture filter for accepted and rejected
traffic at full sampling and enables flow logs at VCN scope, including current
and future subnets and VNICs. Both logs share a dedicated log group and use
`log_retention_duration`, which accepts 30-day increments from 30 through 180
days. Adjust the capture-filter rule in a private module fork if full sampling
is not appropriate for the traffic volume and logging budget.

The Terraform identity needs permission to manage log groups and logs in the
cluster compartment:

```text
Allow group ocf-cluster-admins to manage log-groups in compartment <compartment-name>
Allow group ocf-cluster-admins to read log-content in compartment <compartment-name>
```

Use the `logging` output to connect the log group and individual logs to
archival, SIEM or alarm automation. OCI Audit remains a tenancy service; these
resources add the Kubernetes control-plane and network traffic evidence that
OCI Audit does not replace.

## Network validation

The module rejects invalid IPv4 CIDRs, subnets outside the VCN and any overlap
among the API endpoint, load balancer, node and pod subnets before resource
creation. The defaults reserve a `/19` pod subnet and `/24` subnets for the
other roles. Choose larger ranges before creating a cluster if the capacity
model needs them; changing a subnet CIDR later normally requires replacement.

## Cluster Autoscaler contract

Each node pool may declare boundaries:

```hcl
autoscaling = {
  min_size = 3
  max_size = 9
}
```

Terraform rejects bounds that do not satisfy
`1 <= min_size <= size <= max_size`. The `cluster_autoscaler_nodes` output is
formatted for the OCI managed Cluster Autoscaler add-on `nodes` argument. The
`cluster_autoscaler_node_groups` output exposes the same contract as structured
data.

OCF does not install the add-on or create tenancy IAM policy implicitly. Before
enabling it, grant the `kube-system/cluster-autoscaler` workload identity
permission to manage the selected node pools and their instances. Keep at
least one general-purpose node pool outside the autoscaling set for critical
cluster add-ons. Oracle documents the required identity policy and installation
flow in [Working with the Cluster Autoscaler as a cluster add-on](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengusingclusterautoscaler_topic-Working_with_Cluster_Autoscaler_as_Cluster_Add-on.htm).

## Kubeconfig generation

Use the project command instead of executing a Terraform output as shell code:

```sh
mise run oci:kubeconfig
```

For a private instance:

```sh
mise run oci:instance:kubeconfig -- <instance-name>
```

The scripts read the structured `kubeconfig` output, validate the cluster OCID,
region, endpoint mode, profile and destination, then invoke the OCI CLI as an
argument array. Set an explicit destination when needed:

```sh
OCF_KUBECONFIG_PATH="$PWD/.local/kubeconfigs/prod.yaml" \
  mise run oci:instance:kubeconfig -- prod
```

The destination must be absolute. Old private instances that expose only
`kubeconfig_command` remain supported through strict parsing of the known OCI
CLI flags; arbitrary shell syntax is rejected and never evaluated.

## Terraform state protection

The bootstrap Object Storage bucket has no public access, versioning enabled
and Terraform `prevent_destroy` protection. A normal `terraform destroy`
therefore cannot delete the state bucket. Removing that protection requires a
deliberate source change and a separately reviewed destructive operation.

Keep a tested copy of the backend configuration and OCI credentials outside
the repository. Bucket versioning is recovery support, not a replacement for
an independent state backup and restore drill.
