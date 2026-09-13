# Contributing

Thanks for helping build an open, production-oriented Kubernetes foundation.

## Development setup

```sh
mise trust
mise install
mise run doctor
```

All tooling is pinned in [`mise.toml`](mise.toml). The scripts under
[`scripts/`](scripts) work without mise too, as long as the same tool versions
are on your PATH.

## Checks

CI runs fast documentation, script, Terraform, Kubernetes and supply-chain jobs
on every PR; run them locally before opening one:

```sh
mise run ci:docs         # generated references + Markdown links
mise run ci:scripts      # source policy + shellcheck + unit tests
mise run ci:terraform    # fmt, validate and tflint for every stack
mise run ci:kubernetes   # helmfile render + kubeconform schema validation
mise run ci:supply-chain # immutable dependencies + vulnerability/IaC scans
```

Operational reasoning belongs in
[`docs/implementation-decisions.md`](docs/implementation-decisions.md), not in
source comments. `mise run ci:comments` enforces the narrow exceptions needed
by interpreters, Terraform, ShellCheck and Renovate.

PRs that touch `kubernetes/`, `scripts/` or `test/e2e/` also trigger the
end-to-end suite: it installs the full base on a disposable kind cluster
and traverses the real Envoy data-plane Service through an ephemeral local
forward. It asserts the edge path, certificate issuance, Postgres, Kafka,
cache and monitoring all work. It needs Docker and ~15 minutes:

```sh
mise run ci:e2e                     # OCF_E2E_KEEP=true keeps the cluster
```

The Kubernetes job validates every custom resource against real CRD schemas
from the upstream CRDs catalog. If you add a resource whose kind is missing
from the catalog, the build fails: contribute the schema upstream to
[datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog) or discuss
an exception in the PR.

## How versions are managed

Component versions are pinned in
[`kubernetes/production-base/versions.yaml`](kubernetes/production-base/versions.yaml).
Renovate updates every field annotated with a `# renovate:` comment, the
release-manifest URLs and the container image references in values and
resources.

Manual updates (Renovate does not cover these):

- `strimzi.kafkaVersion` / `kafkaConnectVersion` — coupled with `spec.version`
  and the Connect build image tag in `resources/kafka/*.yaml`; bump together.
- `debezium` — bumping requires recomputing `postgresPluginSha512` and
  updating `resources/kafka/kafka-connect-debezium-postgres.yaml`.
- `appVersion` fields — documentation of what the pinned chart ships; refresh
  them when merging chart bumps.
- Grafana dashboard `gnetId` revisions in `values/grafana.yaml`.

## Adding a component to the Kubernetes base

1. Pin it in `versions.yaml` with a `# renovate:` annotation.
2. Add the repository and release to `helmfile.yaml.gotmpl` behind a profile.
3. Create `values/<component>.yaml` with production-oriented defaults:
   metrics/ServiceMonitor enabled, resources set, secrets via
   `existingSecret`, no credentials in values.
4. Add the namespace with Pod Security Admission labels to
   `manifests/namespace-baseline.yaml`.
5. Add PrometheusRules/dashboards under `resources/monitoring/` when the
   upstream project provides them.
6. Add its `displayName`, regenerate references with `mise run docs:generate`,
   and document secrets, operational constraints and smoke tests.

## Adding a cloud provider

Follow the OCI layout: `terraform/<provider>/bootstrap-state` and
`terraform/<provider>/foundation`, with a self-contained provider module under
`terraform/modules/`. Add the provider to `terraform/provider-contract.yaml`,
map provider terminology to the contract semantics and publish the normalized
`provider_contract` output. The module needs its own SemVer, manifest,
changelog, license, example and Terraform tests. `mise run ci:terraform` must
validate its standalone package before the provider can be marked implemented.

Do not describe a planned provider as supported. Public Terraform Registry
publication requires a separate public repository named
`terraform-<provider>-<name>` with the module at its root and SemVer tags.

## Commits and pull requests

- [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, `test:`.
- One logical change per PR. Include the motivation, not just the diff.
- Never commit real OCIDs, credentials, DNS names or customer identifiers.
  Real cluster instantiations belong in `.local/` (gitignored) or a private
  repository.

## Releases

Releases use calver tags (`vYYYY.M.PATCH`, for example `v2026.7.0`) with notes
in [`CHANGELOG.md`](CHANGELOG.md) summarizing component bumps and any breaking
changes to variables, values or resource layouts.

Before tagging a release:

1. Move the accumulated changelog entries under the dated release heading and
   update every pinned consumption example to the new tag.
2. Run all local checks and the full E2E suite.
3. Push the preparation commit and require the complete CI workflow to pass.
4. Run the E2E workflow manually against that exact commit when path filters do
   not start it automatically.
5. Create an annotated tag on the tested commit, publish the GitHub release from
   the matching changelog section and verify badges and links.
