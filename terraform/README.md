# Terraform

OCI foundation and reusable Terraform module. Other providers are design
targets, not supported implementations.

Provider folders own provider-specific bootstrap, networking, cluster and state
instructions. Shared implementation details live under [`modules/`](modules).

Current providers:

| Provider | Path | Status |
| --- | --- | --- |
| OCI | [`oci/bootstrap-state`](oci/bootstrap-state/README.md) | Implemented |
| OCI | [`oci/foundation`](oci/foundation/README.md) | Implemented |
| Magalu Cloud | `magalu/*` | Planned |
| DigitalOcean | `digitalocean/*` | Planned |

Every implemented module must satisfy
[`provider-contract.yaml`](provider-contract.yaml), carry its own SemVer and
metadata and build as a standalone package. See
[`docs/provider-contract.md`](../docs/provider-contract.md) for the support and
Registry publication rules.

Do not commit real `terraform.tfvars`, `backend.hcl`, private keys or local state files.
