#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

TERRAFORM_DIRS=(
  "terraform/modules/oci-oke-foundation"
  "terraform/oci/bootstrap-state"
  "terraform/oci/foundation"
)

require_command terraform
require_command tflint

log "checking Terraform formatting"
terraform fmt -check -recursive "${OCF_ROOT}/terraform" "${OCF_ROOT}/templates"

for dir in "${TERRAFORM_DIRS[@]}"; do
  log "validating ${dir}"
  terraform -chdir="${OCF_ROOT}/${dir}" init -backend=false -input=false >/dev/null
  terraform -chdir="${OCF_ROOT}/${dir}" validate
done

# The instance template references the module through a path that only
# resolves from .local/instances/<name>/terraform, so validation and linting
# run against a simulated copy of that layout.
log "validating templates/oci-foundation-instance"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TEMPLATE_WORK_DIR="${WORK_DIR}/.local/instances/ci/terraform"
mkdir -p "$TEMPLATE_WORK_DIR" "${WORK_DIR}/terraform/modules"
cp -R "${OCF_ROOT}/templates/oci-foundation-instance/." "$TEMPLATE_WORK_DIR/"
cp -R "${OCF_ROOT}/terraform/modules/oci-oke-foundation" "${WORK_DIR}/terraform/modules/"
terraform -chdir="$TEMPLATE_WORK_DIR" init -backend=false -input=false >/dev/null
terraform -chdir="$TEMPLATE_WORK_DIR" validate

for dir in "${TERRAFORM_DIRS[@]}"; do
  log "linting ${dir}"
  tflint --chdir="${OCF_ROOT}/${dir}" --config="${OCF_ROOT}/.tflint.hcl"
done

log "linting templates/oci-foundation-instance"
tflint --chdir="$TEMPLATE_WORK_DIR" --config="${OCF_ROOT}/.tflint.hcl"

log "terraform checks passed"
