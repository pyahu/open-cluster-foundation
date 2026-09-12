#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/oci.sh
source "${SCRIPT_DIR}/lib/oci.sh"

ACTION="${1:-plan}"
shift || true

AUTO_APPROVE="${OCF_AUTO_APPROVE:-false}"

usage() {
  cat <<'EOF'
Usage:
  scripts/oci-foundation.sh plan
  scripts/oci-foundation.sh apply [--yes]
  scripts/oci-foundation.sh kubeconfig

Environment:
  OCF_AUTO_APPROVE=true    Skip interactive confirmation for apply.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      AUTO_APPROVE="true"
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

FOUNDATION_DIR="${OCF_ROOT}/terraform/oci/foundation"
PLAN_FILE="${FOUNDATION_DIR}/.terraform/ocf-oci-foundation.tfplan"

run_plan() {
  require_command terraform
  require_file "${FOUNDATION_DIR}/backend.hcl" "Run mise run oci:state:apply first, or create backend.hcl from the bootstrap-state output."
  require_file "${FOUNDATION_DIR}/terraform.tfvars" "Copy terraform.tfvars.example and fill the cluster inputs first."

  log "initializing Terraform in ${FOUNDATION_DIR}"
  terraform -chdir="$FOUNDATION_DIR" init -backend-config=backend.hcl

  log "checking Terraform formatting"
  terraform -chdir="$FOUNDATION_DIR" fmt -check -recursive

  log "validating Terraform configuration"
  terraform -chdir="$FOUNDATION_DIR" validate

  log "planning OCI Kubernetes foundation"
  terraform -chdir="$FOUNDATION_DIR" plan -out="$PLAN_FILE"
}

generate_kubeconfig() {
  generate_oci_kubeconfig "$FOUNDATION_DIR"
}

case "$ACTION" in
  plan)
    run_plan
    log "plan saved to ${PLAN_FILE}"
    ;;
  apply)
    run_plan
    confirm_apply "This will create or update OCI networking, OKE and node pool resources" "$AUTO_APPROVE"
    terraform -chdir="$FOUNDATION_DIR" apply "$PLAN_FILE"
    terraform -chdir="$FOUNDATION_DIR" output kubeconfig 2>/dev/null || terraform -chdir="$FOUNDATION_DIR" output kubeconfig_command
    ;;
  kubeconfig)
    generate_kubeconfig
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    die "unknown action: ${ACTION}"
    ;;
esac
