---
title: CLI and toolchain
description: Understand the Open Cluster Foundation mise tasks and their safety boundaries.
---

OCF uses `mise` to pin tool versions and name common workflows. Terraform, Helmfile and kubectl remain visible underneath.

```sh
mise tasks
```

## Workstation

| Command | Purpose |
| --- | --- |
| `mise run doctor` | Check required tools and report optional helpers. |

## OCI state

| Command | Purpose |
| --- | --- |
| `mise run oci:state:plan` | Validate and plan the remote state bucket. |
| `mise run oci:state:apply -- --yes` | Apply the bucket and write the foundation backend. |
| `mise run oci:state:backend` | Recreate the backend file from Terraform output. |

## OKE foundation

| Command | Purpose |
| --- | --- |
| `mise run oci:cluster:plan` | Validate and plan the OKE foundation. |
| `mise run oci:cluster:apply -- --yes` | Apply a reviewed foundation plan. |
| `mise run oci:kubeconfig` | Generate a dedicated kubeconfig from Terraform output. |

## Kubernetes base

| Command | Purpose |
| --- | --- |
| `mise run k8s:base:check` | Detect state and check the current context. |
| `mise run k8s:base:render` | Render the selected Helmfile environment. |
| `mise run k8s:base:apply -- --yes` | Apply the selected environment. |

## Profiles

New clusters select `starter` by default. Use an explicit environment when a cluster needs a different service set.

```sh
mise run k8s:base:render -- --environment production
mise run k8s:base:apply -- --environment production --mode fresh --yes
```

Available environments are `starter`, `production`, `production-ha`, `production-data`, `default` and `all-components`. The `default` environment remains for older OCF installations.

## Validation

| Command | Purpose |
| --- | --- |
| `mise run ci:docs` | Check generated references, writing rules and links. |
| `mise run ci:terraform` | Validate, lint and test every Terraform stack. |
| `mise run ci:kubernetes` | Render profiles and validate resource schemas. |
| `mise run ci:e2e` | Install the base on a disposable Kind cluster. |

:::caution[Before apply]
Verify the OCI profile, Terraform plan, kubeconfig and current Kubernetes context. `--yes` removes the prompt, not the responsibility to review.
:::

The [full CLI reference](https://github.com/pyahu/open-cluster-foundation/blob/main/docs/cli.md) covers instance workflows and every supported option.
