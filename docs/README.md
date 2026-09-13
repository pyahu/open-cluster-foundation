# Open Cluster Foundation documentation

This documentation is organized around the work an operator needs to do. Start
with one path and follow the linked guide when a decision needs more detail.

## Choose a path

### Create a new OCI cluster

Use the OCI foundation when you need OCF to create the network, OKE cluster,
node pools and access path.

1. [Bootstrap remote state](../terraform/oci/bootstrap-state/README.md).
2. [Create the OCI foundation](../terraform/oci/foundation/README.md).
3. [Install the Kubernetes base](../kubernetes/production-base/README.md).

### Install services on an existing cluster

Start with the [Kubernetes production base](../kubernetes/production-base/README.md).
The preflight detects whether the target is fresh, already managed by OCF or a
legacy installation. Review the reported mode before applying anything.

### Upgrade an OCF installation

Read [compatibility and migrations](compatibility.md), then follow the
[lifecycle upgrade procedure](lifecycle.md#upgrade). Existing installations
keep compatible behavior until an operator selects a documented migration.

### Operate or recover a cluster

Use the [lifecycle guide](lifecycle.md) for evidence collection, interrupted
applies, rollback, state recovery, uninstall and disaster recovery. Use
[capacity planning](capacity-planning.md) before enabling high availability or
increasing retention.

### Add a cloud provider

Read the [provider contract](provider-contract.md). A provider is only marked
implemented after its module, package, tests and integration evidence meet the
same contract used by OCI.

## First walkthrough

The following path reaches a reviewed plan without changing cloud or cluster
resources.

### 1. Clone a tested release

```sh
git clone --branch v2026.9.0 --depth 1 \
  https://github.com/pyahu/open-cluster-foundation.git
cd open-cluster-foundation
```

### 2. Install the pinned tools

```sh
mise trust
mise install
mise run doctor
```

`mise.toml` pins Terraform, kubectl, Helm, Helmfile, OCI CLI and the validation
tools used by CI. The `doctor` task reports missing required tools and labels
optional helpers separately.

### 3. Prepare Terraform input

Configure an OCI profile, then copy the example files:

```sh
cp terraform/oci/bootstrap-state/terraform.tfvars.example \
  terraform/oci/bootstrap-state/terraform.tfvars
cp terraform/oci/foundation/terraform.tfvars.example \
  terraform/oci/foundation/terraform.tfvars
```

Fill the copied files with values from your tenancy. They are ignored by Git.
Do not put credentials or customer identifiers in committed examples.

### 4. Review plans

```sh
mise run oci:state:plan
mise run oci:cluster:plan
```

The state bucket must exist before the foundation can use its generated
backend configuration. Follow the detailed OCI guide for that transition.

### 5. Inspect the Kubernetes base

After the cluster exists and a dedicated kubeconfig has been generated:

```sh
mise run k8s:base:check
mise run k8s:base:render -- --environment starter
```

These commands expose the selected mode, profiles and rendered resources before
an installation. The apply command is a separate explicit step.

## The safety model

OCF tries to make risky choices visible:

- Terraform plans are separate from apply tasks.
- Apply tasks require confirmation or `--yes`.
- Kubernetes commands print and verify the current context.
- Fresh and existing clusters follow different compatibility paths.
- The base Gateway is not overwritten after instance specific listeners exist.
- End to end tests use a disposable Kind cluster and a private kubeconfig.
- Real inputs, credentials, state and kubeconfigs live in ignored paths.

These controls reduce accidental changes. They do not remove the need to read a
Terraform plan or understand the target cluster.

## Reference map

| Topic | Document |
| --- | --- |
| Commands and flags | [CLI and toolchain](cli.md) |
| Supported versions | [Compatibility reference](reference/compatibility.md) |
| Installed components | [Component reference](reference/components.md) |
| Upgrade transitions | [Compatibility and migrations](compatibility.md) |
| High availability | [Production HA](production-ha.md) |
| Capacity and cost | [Capacity planning](capacity-planning.md) |
| OCI network hardening | [OCI hardening](oci-hardening.md) |
| Operations and recovery | [Lifecycle](lifecycle.md) |
| Design rationale | [Implementation decisions](implementation-decisions.md) |
| Cloud module requirements | [Provider contract](provider-contract.md) |
| Completed project review | [Remediation report](remediation-report.md) |
