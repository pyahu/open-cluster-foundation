# Terraform Modules

Reusable Terraform modules used by provider foundations.

Modules in this directory are implementation details for the public provider
entrypoints under `terraform/<provider>/`. Users should normally run the
provider entrypoints, not these modules directly.

Current modules:

| Module | Purpose |
| --- | --- |
| [`oci-oke-foundation`](oci-oke-foundation) | OCI networking, OKE cluster and node pool foundation. |
