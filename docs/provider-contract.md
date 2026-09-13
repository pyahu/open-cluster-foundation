# Terraform provider contract

Open Cluster Foundation currently implements one cloud foundation: OCI OKE.
The Kubernetes production base can run on conformant Kubernetes clusters, but
that portability does not make the Terraform layer multi-cloud. Magalu Cloud
and DigitalOcean remain roadmap entries until their modules pass the same
contract and provider-specific integration evidence exists.

The machine-readable contract is
[`terraform/provider-contract.yaml`](../terraform/provider-contract.yaml).
It defines stable semantic inputs, the required normalized
`provider_contract` output and the support status of every named provider.
Provider terminology may differ where the cloud primitive differs; for
example, the contract's network CIDR maps to OCI `vcn_cidr`. Node-pool provider
extensions such as shape names are allowed, while size, labels and taints are
common requirements.

## Support levels

`planned` means no consumable module exists and no support claim is allowed.
`implemented` requires a module directory, provider entrypoint, SemVer,
manifest, changelog, license, example, mock contract tests, formatting,
validation, linting and standalone packaging in CI. Production support also
requires provider integration evidence maintained by that provider's
contributors; mock tests alone are not evidence that a cloud implementation
works.

The OCI module is implemented and its compatibility is checked read-only
against a live OKE installation. The repository does not run destructive cloud
integration tests and does not automatically apply changes to that cluster.

## Versioning

The monorepo uses calendar versions for project releases. Every provider
module carries an independent Semantic Version in its `VERSION` and
`module.yaml` files. A module version changes according to its Terraform input,
output and resource behavior:

- Patch: compatible fixes with no intended interface change.
- Minor: backward-compatible inputs, outputs or capabilities.
- Major: incompatible input/output changes or resource behavior that requires
  an explicit migration.

The provider contract has its own Semantic Version. A provider module records
the contract version it implements. Adding optional fields is compatible;
removing or changing required semantics requires a new contract major version.

## Standalone package and Registry

Build the OCI package into a new destination:

```sh
scripts/package-terraform-module.sh oci-oke-foundation /absolute/output/path
```

The command copies only module source, tests, examples, metadata and the
project license. It excludes local Terraform state, `.terraform` directories
and dependency lock files. CI initializes, validates and tests the resulting
standalone tree, which detects accidental dependencies on the monorepo.

The public Terraform Registry cannot publish this module directly from the
current repository. It requires a public GitHub repository named
`terraform-oci-oke-foundation`, Terraform files at that repository's root and
SemVer tags. After the standalone package is moved to that dedicated
repository and its release pipeline is tested, the intended address is
`pyahu/oke-foundation/oci`. Until then, consumers must use a commit or released
project tag with the Git source subdirectory and must not use that Registry
address.

These requirements follow HashiCorp's
[module publication](https://developer.hashicorp.com/terraform/registry/modules/publish)
and [standard module structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
contracts.
