#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-plan}"
shift || true

AUTO_APPROVE="${OCF_AUTO_APPROVE:-false}"
WRITE_BACKEND="true"

usage() {
  cat <<'EOF'
Usage:
  scripts/oci-bootstrap-state.sh plan
  scripts/oci-bootstrap-state.sh apply [--yes] [--skip-backend-write]
  scripts/oci-bootstrap-state.sh backend

Environment:
  OCF_AUTO_APPROVE=true    Skip interactive confirmation for apply.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      AUTO_APPROVE="true"
      ;;
    --skip-backend-write)
      WRITE_BACKEND="false"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

BOOTSTRAP_DIR="${OCF_ROOT}/terraform/oci/bootstrap-state"
FOUNDATION_DIR="${OCF_ROOT}/terraform/oci/foundation"
PLAN_FILE="${BOOTSTRAP_DIR}/.terraform/ocf-bootstrap-state.tfplan"

write_backend() {
  local backend_file="${FOUNDATION_DIR}/backend.hcl"
  local backend_tmp="${backend_file}.tmp"

  log "writing Terraform backend config to ${backend_file}"
  terraform -chdir="$BOOTSTRAP_DIR" output -raw backend_hcl > "$backend_tmp"
  mv "$backend_tmp" "$backend_file"
}

run_plan() {
  require_command terraform
  require_file "${BOOTSTRAP_DIR}/terraform.tfvars" "Copy terraform.tfvars.example and fill the OCI tenancy, compartment and region first."

  log "initializing Terraform in ${BOOTSTRAP_DIR}"
  terraform -chdir="$BOOTSTRAP_DIR" init

  log "checking Terraform formatting"
  terraform -chdir="$BOOTSTRAP_DIR" fmt -check -recursive

  log "validating Terraform configuration"
  terraform -chdir="$BOOTSTRAP_DIR" validate

  log "planning OCI remote state bucket"
  terraform -chdir="$BOOTSTRAP_DIR" plan -out="$PLAN_FILE"
}

case "$ACTION" in
  plan)
    run_plan
    log "plan saved to ${PLAN_FILE}"
    ;;
  apply)
    run_plan
    confirm_apply "This will create or update OCI Object Storage resources for Terraform state" "$AUTO_APPROVE"
    terraform -chdir="$BOOTSTRAP_DIR" apply "$PLAN_FILE"
    if [[ "$WRITE_BACKEND" == "true" ]]; then
      write_backend
    fi
    ;;
  backend)
    require_command terraform
    write_backend
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    die "unknown action: ${ACTION}"
    ;;
esac
