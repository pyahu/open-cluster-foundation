---
title: Getting started
description: Reach a reviewed Open Cluster Foundation plan without changing cloud or Kubernetes resources.
head:
  - tag: meta
    attrs:
      name: robots
      content: index, follow
---

Open Cluster Foundation creates an OCI OKE foundation and installs a selected set of cluster services. This guide prepares the toolchain and inspects the target. It does not change cloud or Kubernetes resources until you choose an apply command.

<div class="ocf-actions">
  <a href="#clone-a-tested-release">Start the guide</a>
  <a href="https://github.com/pyahu/open-cluster-foundation">View on GitHub</a>
</div>

:::note[Current scope]
OCI OKE is implemented. Kubernetes 1.36.1 is installed and exercised by the end to end pipeline.
:::

## Before you begin

You need an OCI tenancy, permission to create the documented resources and a workstation with `git` and [mise](https://mise.jdx.dev/). Use a separate OCI profile and kubeconfig for OCF work.

## Clone a tested release

Use an immutable release for a real installation. The current tested release is `v2026.9.0`.

```sh
git clone --branch v2026.9.0 --depth 1 \
  https://github.com/pyahu/open-cluster-foundation.git
cd open-cluster-foundation
```

## Install the pinned tools

```sh
mise trust
mise install
mise run doctor
```

The repository pins Terraform, kubectl, Helm, Helmfile, OCI CLI and the validation tools used in CI.

## Prepare local input

Configure an OCI profile and copy the example variable files. The local copies are ignored by Git.

```sh
cp terraform/oci/bootstrap-state/terraform.tfvars.example \
  terraform/oci/bootstrap-state/terraform.tfvars
cp terraform/oci/foundation/terraform.tfvars.example \
  terraform/oci/foundation/terraform.tfvars
```

Fill them with values from your tenancy. Keep credentials, OCIDs and customer names out of committed examples.

## Review the Terraform plans

```sh
mise run oci:state:plan
mise run oci:cluster:plan
```

The state bucket must exist before the cluster plan can use its generated backend. Follow the [OCI guides](https://github.com/pyahu/open-cluster-foundation/tree/main/terraform/oci) when you are ready to apply either layer.

## Inspect the Kubernetes target

After OKE exists and a dedicated kubeconfig has been generated:

```sh
mise run k8s:base:check
mise run k8s:base:render -- --environment starter
```

The preflight prints the current context, detected installation mode and selected profile. Read the output before applying the base.

:::caution[Apply changes real infrastructure]
Verify the OCI profile, Terraform plan, kubeconfig and Kubernetes context before every apply. The `--yes` flag removes the prompt. It does not remove the need to review the target.
:::

## Choose the next path

- Read [CLI and toolchain](/docs/cli/) to understand tasks, flags and apply boundaries.
- Read [Architecture](/docs/architecture/) to see what Terraform, Helmfile and application teams own.
- Read the [lifecycle guide](https://github.com/pyahu/open-cluster-foundation/blob/main/docs/lifecycle.md) before planning upgrades, recovery or removal.
