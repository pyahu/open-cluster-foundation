# CLI and toolchain

OCF uses `mise` as a small command layer over Terraform, OCI CLI, Helmfile and
kubectl. This keeps tool versions and common workflows in one place without
hiding the commands they run.

List every task with its current description:

```sh
mise tasks
```

## Install the toolchain

```sh
mise trust
mise install
mise run doctor
```

The pinned versions live in [`mise.toml`](../mise.toml). Required tools fail the
doctor task when missing. Optional navigation tools are reported without
blocking the workflow.

## OCI state

| Task | Purpose |
| --- | --- |
| `mise run oci:state:plan` | Validate and plan the remote state bucket |
| `mise run oci:state:apply -- --yes` | Apply the bucket and write `backend.hcl` |
| `mise run oci:state:backend` | Recreate `backend.hcl` from Terraform output |

Run the plan first. The foundation expects the generated backend file before it
can initialize remote state.

## OCI foundation

| Task | Purpose |
| --- | --- |
| `mise run oci:cluster:plan` | Validate and plan the OKE foundation |
| `mise run oci:cluster:apply -- --yes` | Apply the reviewed foundation plan |
| `mise run oci:kubeconfig` | Generate kubeconfig from Terraform output |

The apply task accepts `--yes` for noninteractive use. Without it, the script
asks for confirmation.

## Private instances

The instance tasks create ignored working directories under
`.local/instances/<name>`. Use them when real tenant values should remain
separate from the public foundation example.

```sh
mise run oci:instance:new -- production
mise run oci:instance:plan -- production
mise run oci:instance:apply -- production --yes
mise run oci:instance:kubeconfig -- production
```

## Kubernetes base

| Task | Purpose |
| --- | --- |
| `mise run k8s:base:check` | Detect the target state and run preflight checks |
| `mise run k8s:base:render` | Render the selected Helmfile environment |
| `mise run k8s:base:apply -- --yes` | Apply the selected environment |
| `mise run k8s:gateway:check-access` | Check namespaces before restricting route attachment |
| `mise run k8s:nodes:taint-database -- --yes` | Apply database node labels and taints |

Select an environment explicitly when you do not want automatic selection:

```sh
mise run k8s:base:check -- --environment production --mode fresh
mise run k8s:base:render -- --environment production
mise run k8s:base:apply -- --environment production --mode fresh --yes
```

Supported environments are `starter`, `production`, `production-ha`,
`production-data`, `default` and `all-components`. The `default` environment is
for compatibility with existing installations. New clusters select `starter`
when no environment is provided.

Upgrade flags are documented in [compatibility and migrations](compatibility.md).
Do not guess a migration value on a running cluster.

## Project validation

| Task | Checks |
| --- | --- |
| `mise run ci:docs` | Generated references, editorial rules and Markdown links |
| `mise run ci:site` | Landing page, documentation routes and local links |
| `mise run ci:scripts` | Shellcheck, source policy and shell unit tests |
| `mise run ci:terraform` | Format, validation, lint, contract tests and packages |
| `mise run ci:kubernetes` | Helmfile rendering and schema validation |
| `mise run ci:supply-chain` | Pins, image policy, vulnerability and IaC scans |
| `mise run ci:e2e` | Full installation on a disposable Kind cluster |

Run the focused check while editing. Run all affected checks before committing.
The E2E task creates its own kubeconfig and does not use the current kubectl
context.

Run the landing page and web documentation with the pinned Cloudflare runtime:

```sh
mise run site:build
mise run site:dev
```

The [website deployment guide](site.md) documents Cloudflare Pages Git
integration and the protected manual deploy task.

## Direct script help

The `mise` tasks call scripts under `scripts/`. Their help output is available
without changing infrastructure:

```sh
scripts/oci-bootstrap-state.sh --help
scripts/oci-foundation.sh --help
scripts/oci-instance.sh --help
scripts/k8s-production-base.sh --help
```

Prefer the `mise` entrypoints for normal use because they run with the pinned
toolchain.
