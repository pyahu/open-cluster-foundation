# Terraform Modules

Reusable Terraform modules used by provider foundations.

Modules in this directory back the public provider entrypoints under
`terraform/<provider>/`. Each implemented provider module has an independent
SemVer, manifest, changelog, license, examples and conformance tests. Users
should normally run the provider entrypoint until a module has been extracted
to its dedicated Registry repository.

Current modules:

| Module | Purpose |
| --- | --- |
| [`oci-oke-foundation`](oci-oke-foundation) | OCI networking, OKE cluster and node pool foundation. |

The current repository name and monorepo layout do not satisfy the public
Terraform Registry repository contract. `scripts/package-terraform-module.sh`
builds the standalone source tree intended for
`terraform-oci-oke-foundation`; it does not publish it.
