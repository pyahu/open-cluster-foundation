#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

require_command rg
require_command trivy
require_command yq

validate_action_references() {
  local file
  local line
  local declaration
  local action
  local reference

  while IFS=: read -r file line declaration; do
    action="${declaration#uses: }"
    [[ "$action" == ./* ]] && continue
    reference="${action##*@}"
    [[ "$reference" =~ ^[0-9a-f]{40}$ ]] || die "mutable action reference at ${file}:${line}: ${action}"
  done < <(rg --no-heading --line-number --only-matching 'uses: [^[:space:]]+' "${OCF_ROOT}/.github/workflows")
}

validate_image() {
  local source_file="$1"
  local image="$2"
  local require_digest="$3"
  local image_name
  local tag

  [[ "$image" == */* ]] || die "unqualified image in ${source_file}: ${image}"
  if [[ "$image" =~ @sha256:[0-9a-f]{64}$ ]]; then
    return
  fi
  [[ "$require_digest" == "false" ]] || die "image must use an immutable digest in ${source_file}: ${image}"

  image_name="${image##*/}"
  [[ "$image_name" == *:* ]] || die "image has no explicit tag or digest in ${source_file}: ${image}"
  tag="${image_name##*:}"
  case "$tag" in
    latest | main | master | stable | edge | nightly)
      die "mutable image tag in ${source_file}: ${image}"
      ;;
  esac
}

validate_images() {
  local source_file
  local image
  local require_digest

  while IFS= read -r -d '' source_file; do
    require_digest=false
    [[ "$source_file" == "${OCF_ROOT}/test/e2e/"* ]] && require_digest=true
    while IFS= read -r image; do
      [[ -n "$image" ]] && validate_image "$source_file" "$image" "$require_digest"
    done < <(yq ea -N -r '.. | select(tag == "!!map") | (.image // .imageName // "") | select(tag == "!!str" and . != "")' "$source_file")
  done < <(find \
    "${OCF_ROOT}/kubernetes/production-base/manifests" \
    "${OCF_ROOT}/kubernetes/production-base/resources" \
    "${OCF_ROOT}/test/e2e" \
    -name '*.yaml' -print0)

  while IFS= read -r image; do
    [[ -n "$image" ]] && validate_image "scripts/ci-e2e.sh" "$image" true
  done < <(rg --only-matching --no-filename -- '--image=[^[:space:]\\]+' "${OCF_ROOT}/scripts/ci-e2e.sh" | cut -d= -f2)
}

validate_remote_artifacts() {
  local component
  local artifact
  local commit
  local checksum_key

  commit="$(component_value crdCatalog commit)"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "CRD catalog must use an immutable Git commit"
  commit="$(component_value helmDiff commit)"
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "helm diff must use an immutable Git commit"

  for checksum_key in linuxAmd64Sha256 linuxArm64Sha256 macosAmd64Sha256 macosArm64Sha256; do
    [[ "$(component_value helmDiff "$checksum_key")" =~ ^[0-9a-f]{64}$ ]] ||
      die "helm diff ${checksum_key} must be a SHA-256 digest"
  done

  for component in calico pluginBarmanCloud rabbitmqClusterOperator rabbitmqMessagingTopologyOperator prometheusOperatorCrds; do
    artifact="${WORK_DIR}/${component}.yaml"
    download_verified \
      "$(component_value "$component" manifest)" \
      "$(component_value "$component" manifestSha256)" \
      "$artifact"
  done
}

run_trivy() {
  local target
  local template_work_dir
  local scan_args=(
    --severity "HIGH,CRITICAL"
    --exit-code 1
    --skip-dirs .terraform
    --skip-version-check
  )

  for target in terraform kubernetes/production-base test/e2e; do
    trivy config "${scan_args[@]}" \
      --skip-files 'kubernetes/production-base/patches/*.yaml' \
      "${OCF_ROOT}/${target}"
  done

  template_work_dir="${WORK_DIR}/.local/instances/ci/terraform"
  mkdir -p "$template_work_dir" "${WORK_DIR}/terraform/modules"
  cp -R "${OCF_ROOT}/templates/oci-foundation-instance/." "$template_work_dir/"
  cp -R "${OCF_ROOT}/terraform/modules/oci-oke-foundation" "${WORK_DIR}/terraform/modules/"
  trivy config "${scan_args[@]}" "$template_work_dir"

  trivy fs \
    --scanners vuln \
    --severity CRITICAL \
    --ignore-unfixed \
    --exit-code 1 \
    --skip-dirs .git \
    --skip-dirs .local \
    --skip-dirs .terraform \
    --skip-version-check \
    "$OCF_ROOT"
}

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log "validating immutable GitHub Actions"
validate_action_references
log "validating pinned remote artifacts"
validate_remote_artifacts
log "validating container image policy"
validate_images
log "scanning vulnerabilities and infrastructure configuration"
run_trivy
log "supply-chain checks passed"
