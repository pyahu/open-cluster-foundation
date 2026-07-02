#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-}"
INSTANCE_NAME="${2:-}"
AUTO_APPROVE="${OCF_AUTO_APPROVE:-false}"

usage() {
  cat <<'EOF'
Usage:
  scripts/oci-instance.sh new <instance-name>
  scripts/oci-instance.sh plan <instance-name>
  scripts/oci-instance.sh apply <instance-name> [--yes]
  scripts/oci-instance.sh kubeconfig <instance-name>

Instances live under .local/instances/<instance-name>/terraform and are ignored
by Git. Keep real OCIDs, backend files, tfvars and customer identifiers there or
in a separate private repository.
EOF
}

if [[ -z "$ACTION" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$INSTANCE_NAME" ]]; then
  usage
  die "missing instance name"
fi

shift 2 || true

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

case "$INSTANCE_NAME" in
  *[!a-z0-9-]* | "" | -*)
    die "instance name must be lowercase alphanumeric or hyphen and must not start with a hyphen"
    ;;
esac

TEMPLATE_DIR="${OCF_ROOT}/templates/oci-foundation-instance"
INSTANCE_DIR="${OCF_ROOT}/.local/instances/${INSTANCE_NAME}/terraform"
PLAN_FILE="${INSTANCE_DIR}/.terraform/ocf-${INSTANCE_NAME}.tfplan"

new_instance() {
  require_command cp
  require_command mkdir

  if [[ -e "$INSTANCE_DIR" ]]; then
    die "instance already exists: ${INSTANCE_DIR}"
  fi

  mkdir -p "$INSTANCE_DIR"
  cp -R "${TEMPLATE_DIR}/." "$INSTANCE_DIR/"

  log "created private OCI instance at ${INSTANCE_DIR}"
  log "next: copy backend.hcl.example to backend.hcl and terraform.tfvars.example to terraform.tfvars"
}

run_plan() {
  require_command terraform
  require_file "${INSTANCE_DIR}/backend.hcl" "Copy backend.hcl.example and fill the remote state backend."
  require_file "${INSTANCE_DIR}/terraform.tfvars" "Copy terraform.tfvars.example and fill the OCI inputs."

  log "initializing Terraform in ${INSTANCE_DIR}"
  terraform -chdir="$INSTANCE_DIR" init -backend-config=backend.hcl

  log "checking Terraform formatting"
  terraform -chdir="$INSTANCE_DIR" fmt -check -recursive

  log "validating Terraform configuration"
  terraform -chdir="$INSTANCE_DIR" validate

  log "planning OCI foundation instance ${INSTANCE_NAME}"
  terraform -chdir="$INSTANCE_DIR" plan -out="$PLAN_FILE"
}

generate_kubeconfig() {
  require_command terraform
  require_command oci
  require_file "${INSTANCE_DIR}/terraform.tfvars" "The instance has not been configured yet."

  local command_text
  command_text="$(terraform -chdir="$INSTANCE_DIR" output -raw kubeconfig_command)"

  log "running kubeconfig command from Terraform output"
  printf '%s\n' "$command_text"
  eval "$command_text"
}

case "$ACTION" in
  new)
    new_instance
    ;;
  plan)
    run_plan
    log "plan saved to ${PLAN_FILE}"
    ;;
  apply)
    run_plan
    confirm_apply "This will create or update OCI resources for private instance ${INSTANCE_NAME}" "$AUTO_APPROVE"
    terraform -chdir="$INSTANCE_DIR" apply "$PLAN_FILE"
    terraform -chdir="$INSTANCE_DIR" output kubeconfig_command
    ;;
  kubeconfig)
    generate_kubeconfig
    ;;
  *)
    usage
    die "unknown action: ${ACTION}"
    ;;
esac
