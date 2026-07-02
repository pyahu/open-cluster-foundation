# OCI Foundation Instance Template

This template is for private, customer-specific OCI cluster instances that use
the public Open Cluster Foundation Terraform module.

Do not commit rendered instances that contain real tenancy OCIDs, compartment
OCIDs, backend bucket names, allowlisted IPs, DNS names, tags, or customer
identifiers. Generate them under `.local/instances/<name>/terraform` or keep
them in a separate private repository.

When this template is copied outside this repository, update the module
`source` in `main.tf` to a pinned Git reference, for example:

```hcl
source = "github.com/<org>/open-cluster-foundation//terraform/modules/oci-oke-foundation?ref=v0.1.0"
```

## Local Instance Flow

From the repository root:

```sh
scripts/oci-instance.sh new <instance-name>
cd .local/instances/<instance-name>/terraform
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

Then fill in the real OCI values:

```sh
${EDITOR:-vi} backend.hcl
${EDITOR:-vi} terraform.tfvars
```

Plan and apply:

```sh
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -out=.terraform/plan.tfplan
terraform apply .terraform/plan.tfplan
```

Generate kubeconfig from the Terraform output:

```sh
terraform output -raw kubeconfig_command
$(terraform output -raw kubeconfig_command)
```

## Node Pools

The template starts with two node pools:

- `worker`: general workloads and cluster add-ons.
- `database`: database workloads that should be isolated through labels and
  Kubernetes taints.

Labels and taints declared in `node_pools` are registered by kubelet at node
startup, so nodes created by scaling or node cycling come up already tainted.
For nodes created before taints were configured, and to add the
`node-role.kubernetes.io/postgres` label (which kubelet cannot self-apply),
run:

```sh
mise run k8s:nodes:taint-database -- --yes
```
