#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

required_status=0
optional_status=0

check_required() {
  local command_name="$1"
  local version_command="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       required %-16s ' "$command_name"
    eval "$version_command" | sed -n '1p'
  else
    printf 'missing  required %-16s install it before running the related task\n' "$command_name"
    required_status=1
  fi
}

check_optional() {
  local command_name="$1"
  local version_command="$2"
  local note="$3"

  if command -v "$command_name" >/dev/null 2>&1; then
    printf 'ok       optional %-16s ' "$command_name"
    eval "$version_command" | sed -n '1p'
  else
    printf 'missing  optional %-16s %s\n' "$command_name" "$note"
    optional_status=1
  fi
}

check_required terraform 'terraform version | sed -n "1p"'
check_required kubectl 'kubectl version --client=true --short 2>/dev/null || kubectl version --client=true | sed -n "1p"'
check_required helm 'helm version --short'
check_required helmfile 'helmfile --version'
check_required jq 'jq --version'
check_required yq 'yq --version'
check_required openssl 'openssl version'
check_required python3 'python3 --version'

check_optional oci 'oci --version' 'required for OCI provisioning tasks'
check_optional doctl 'doctl version | sed -n "1p"' 'required for future DigitalOcean tasks'
check_optional mgc 'mgc --version 2>/dev/null || mgc version 2>/dev/null || printf "mgc installed\n"' 'required for future Magalu Cloud tasks'
check_optional kubectx 'kubectx --help 2>/dev/null | sed -n "1p"; true' 'useful for switching Kubernetes contexts'
check_optional kubens 'kubens --help 2>/dev/null | sed -n "1p"; true' 'useful for switching Kubernetes namespaces'
check_optional kustomize 'kustomize version' 'useful for Kubernetes manifest workflows'
check_optional tflint 'tflint --version | sed -n "1p"' 'useful before publishing Terraform changes'
check_optional terraform-docs 'terraform-docs version' 'useful for generating Terraform module docs'
check_optional kubeconform 'kubeconform -v' 'useful for Kubernetes schema validation'
check_optional k9s 'k9s version --short 2>/dev/null || k9s version | sed -n "1p"' 'useful for cluster inspection'
check_optional stern 'stern --version' 'useful for log tailing'

if [[ "$optional_status" -ne 0 ]]; then
  printf '\nInstall pinned tools with: mise install\n'
fi

exit "$required_status"
