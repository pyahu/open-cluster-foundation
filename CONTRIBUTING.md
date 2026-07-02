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

CI runs three jobs; run them locally before opening a PR:

```sh
mise run ci:scripts      # shellcheck
mise run ci:terraform    # fmt, validate and tflint for every stack
mise run ci:kubernetes   # helmfile render + kubeconform schema validation
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
6. Document the component in `kubernetes/production-base/README.md`
   (component matrix, secrets, smoke tests).

## Adding a cloud provider

Follow the OCI layout: `terraform/<provider>/bootstrap-state` and
`terraform/<provider>/foundation`, with provider-specific modules under
`terraform/modules/`. Providers should expose comparable inputs and outputs
(cluster name, kubernetes version, node pools with labels/taints, CIDR
allowlists) so the Kubernetes base stays provider-agnostic.

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
