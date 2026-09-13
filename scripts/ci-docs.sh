#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

GENERATED_ROOT="$(mktemp -d)"
trap 'rm -rf "$GENERATED_ROOT"' EXIT

require_command lychee
require_command yq

VERSIONS_FILE="${OCF_ROOT}/kubernetes/production-base/versions.yaml"
E2E_KUBERNETES_VERSION="$(yq -er '.e2e.kubernetesVersion' "$VERSIONS_FILE")"
KIND_NODE_IMAGE="$(yq -er '.e2e.kindNodeImage' "$VERSIONS_FILE")"
KIND_NODE_DIGEST="${KIND_NODE_IMAGE##*@sha256:}"
[[ "$(yq -r '.minimumKubernetesVersion' "$VERSIONS_FILE")" =~ ^[0-9]+\.[0-9]+$ ]] || die "minimum Kubernetes version must use major.minor"
[[ "$E2E_KUBERNETES_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "E2E Kubernetes version must use major.minor.patch"
[[ "$KIND_NODE_IMAGE" == "kindest/node:v${E2E_KUBERNETES_VERSION}@sha256:${KIND_NODE_DIGEST}" && "$KIND_NODE_DIGEST" =~ ^[0-9a-f]{64}$ ]] || die "E2E node image must pin the documented Kubernetes version by digest"
[[ "$(yq -r '[.components[] | select(.displayName == null or .displayName == "")] | length' "$VERSIONS_FILE")" == "0" ]] || die "every component must have a displayName"
[[ "$(yq -r '[.components[].displayName | select((contains("|")) or (contains("\n")))] | length' "$VERSIONS_FILE")" == "0" ]] || die "component display names must be valid Markdown table cells"
for environment_file in "${OCF_ROOT}"/kubernetes/production-base/environments/*.yaml; do
  [[ "$(yq -r '.description // ""' "$environment_file")" != "" ]] || die "${environment_file#"${OCF_ROOT}"/} needs a description"
  [[ "$(yq -r '(.description | contains("|")) or (.description | contains("\n"))' "$environment_file")" == "false" ]] || die "${environment_file#"${OCF_ROOT}"/} description must be a valid Markdown table cell"
  [[ "$(yq -r '[.profiles[] | select(type != "!!bool")] | length' "$environment_file")" == "0" ]] || die "${environment_file#"${OCF_ROOT}"/} profile values must be booleans"
done

"${SCRIPT_DIR}/generate-docs.sh" "$GENERATED_ROOT"
for document_name in components.md compatibility.md; do
  expected="${OCF_ROOT}/docs/reference/${document_name}"
  generated="${GENERATED_ROOT}/reference/${document_name}"
  require_file "$expected"
  cmp -s "$expected" "$generated" || die "${expected#"${OCF_ROOT}"/} is stale; run mise run docs:generate"
done

lychee --offline --no-progress --root-dir "$OCF_ROOT" "${OCF_ROOT}/**/*.md"
log "documentation checks passed"
