#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

CONTRACT_FILE="${OCF_ROOT}/terraform/provider-contract.yaml"
PACKAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$PACKAGE_ROOT"' EXIT

require_command rg
require_command terraform
require_command yq
require_file "$CONTRACT_FILE"

[[ "$(yq -r '.metadata.version' "$CONTRACT_FILE")" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "provider contract version must use SemVer"
[[ "$(yq -r '[.providers[] | select(.status == "implemented")] | length' "$CONTRACT_FILE")" -gt 0 ]] || die "provider contract must contain at least one implemented provider"
[[ "$(yq -r '([.providers[].name] | length) == ([.providers[].name] | unique | length)' "$CONTRACT_FILE")" == "true" ]] || die "provider contract contains duplicate provider names"
[[ "$(yq -r '[.providers[].status | select(. != "implemented" and . != "planned")] | length' "$CONTRACT_FILE")" == "0" ]] || die "provider contract contains an unknown support status"

while IFS=$'\t' read -r provider module_path module_version registry_address registry_repository; do
  module_directory="${OCF_ROOT}/${module_path}"
  module_name="${module_path##*/}"
  module_manifest="${module_directory}/module.yaml"

  require_file "${module_directory}/README.md"
  require_file "${module_directory}/variables.tf"
  require_file "${module_directory}/outputs.tf"
  require_file "${module_directory}/versions.tf"
  require_file "${module_directory}/VERSION"
  require_file "${module_directory}/CHANGELOG.md"
  require_file "${module_directory}/LICENSE"
  require_file "${module_directory}/tests/contracts.tftest.hcl"
  require_file "$module_manifest"

  diff -q -B "${OCF_ROOT}/LICENSE" "${module_directory}/LICENSE" >/dev/null || die "${module_name} license differs from the project license"
  [[ "$(<"${module_directory}/VERSION")" == "$module_version" ]] || die "${module_name} VERSION does not match provider-contract.yaml"
  [[ "$module_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "${module_name} version must use SemVer"
  [[ "$(yq -r '.metadata.version' "$module_manifest")" == "$module_version" ]] || die "${module_name} manifest version does not match"
  [[ "$(yq -r '.spec.provider' "$module_manifest")" == "$provider" ]] || die "${module_name} manifest provider does not match"
  [[ "$(yq -r '.spec.contractVersion' "$module_manifest")" == "$(yq -r '.metadata.version' "$CONTRACT_FILE")" ]] || die "${module_name} contract version does not match"
  [[ "$(yq -r '.spec.registry.address' "$module_manifest")" == "$registry_address" ]] || die "${module_name} registry address does not match"
  [[ "$(yq -r '.spec.registry.repository' "$module_manifest")" == "$registry_repository" ]] || die "${module_name} registry repository does not match"
  registry_publication="$(yq -r '.spec.registry.publication' "$module_manifest")"
  [[ "$registry_publication" == "dedicated-repository-required" ]] || die "${module_name} must not claim direct public Registry publication from the monorepo"
  [[ "$registry_repository" == terraform-"$provider"-* ]] || die "${module_name} registry repository violates the public Registry naming contract"
  [[ "$registry_address" == */"$provider" ]] || die "${module_name} registry address must end with its provider system"
  evidence_mode="$(PROVIDER="$provider" yq -er '.providers[] | select(.name == strenv(PROVIDER)) | .evidence.mode' "$CONTRACT_FILE")"
  evidence_kubernetes_version="$(PROVIDER="$provider" yq -er '.providers[] | select(.name == strenv(PROVIDER)) | .evidence.kubernetesVersion' "$CONTRACT_FILE")"
  evidence_observed_at="$(PROVIDER="$provider" yq -er '.providers[] | select(.name == strenv(PROVIDER)) | .evidence.observedAt' "$CONTRACT_FILE")"
  [[ "$evidence_mode" == "read-only" || "$evidence_mode" == "integration" ]] || die "${module_name} evidence mode must be read-only or integration"
  [[ "$evidence_kubernetes_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "${module_name} evidence Kubernetes version must use major.minor.patch"
  [[ "$evidence_observed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "${module_name} evidence observation date must use YYYY-MM-DD"
  rg -q "^## ${module_version}$" "${module_directory}/CHANGELOG.md" || die "${module_name} changelog does not contain its current version"
  rg -q 'source[[:space:]]*=[[:space:]]*"\.\./\.\."' "${module_directory}/examples" -g '*.tf' || die "${module_name} unpublished example must use its packaged module"

  for input_name in $(yq -r '.spec.inputs.required[]' "$CONTRACT_FILE"); do
    rg -q "^variable \"${input_name}\"" "${module_directory}/variables.tf" || die "${module_name} is missing contract input ${input_name}"
  done
  rg -q '^output "provider_contract"' "${module_directory}/outputs.tf" || die "${module_name} is missing the provider_contract output"
  if rg -n 'source[[:space:]]*=[[:space:]]*"\.\./' "$module_directory" -g '*.tf' -g '!**/examples/**'; then
    die "${module_name} depends on Terraform source outside its package"
  fi

  package_directory="$("${SCRIPT_DIR}/package-terraform-module.sh" "$module_name" "$PACKAGE_ROOT")"
  cmp -s "${OCF_ROOT}/LICENSE" "${package_directory}/LICENSE" || die "${module_name} package license differs from the project license"
  [[ ! -e "${package_directory}/.terraform.lock.hcl" ]] || die "${module_name} package must not include a dependency lock file"

  terraform -chdir="$package_directory" fmt -check -recursive
  terraform -chdir="$package_directory" init -backend=false -input=false >/dev/null
  terraform -chdir="$package_directory" validate >/dev/null
  terraform -chdir="$package_directory" test >/dev/null
  log "provider module ${provider}/${module_name} ${module_version} satisfies contract $(yq -r '.metadata.version' "$CONTRACT_FILE")"
done < <(yq -r '.providers[] | select(.status == "implemented") | [.name, .modulePath, .moduleVersion, .registryAddress, .registryRepository] | @tsv' "$CONTRACT_FILE")
