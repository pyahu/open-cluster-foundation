# Terraform

Cloud-provider foundations and reusable Terraform modules.

Provider folders own provider-specific bootstrap, networking, cluster and state
instructions. Shared implementation details live under [`modules/`](modules).

Current providers:

| Provider | Path | Status |
| --- | --- | --- |
| OCI | [`oci/bootstrap-state`](oci/bootstrap-state/README.md) | Implemented |
| OCI | [`oci/foundation`](oci/foundation/README.md) | Implemented |
| Magalu Cloud | `magalu/*` | Planned |
| DigitalOcean | `digitalocean/*` | Planned |

Do not commit real `terraform.tfvars`, `backend.hcl`, private keys or local state files.
