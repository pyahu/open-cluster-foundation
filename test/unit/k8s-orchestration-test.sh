#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCF_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

source "${OCF_ROOT}/scripts/k8s-production-base.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

BASE_DIR="${OCF_ROOT}/kubernetes/production-base"
ENVIRONMENT=starter
GATEWAY_CLASS_PRESENT=false
GATEWAY_PRESENT=false
KUBECTL_APPLIES="${TEST_ROOT}/kubectl-applies"

kubectl() {
  if [[ "$*" == "get gatewayclass envoy" ]]; then
    [[ "$GATEWAY_CLASS_PRESENT" == "true" ]]
    return
  fi
  if [[ "$*" == "-n platform-system get gateway public-gateway" ]]; then
    [[ "$GATEWAY_PRESENT" == "true" ]]
    return
  fi
  if [[ "$*" == "apply -f -" ]]; then
    yq -r '.kind' >>"$KUBECTL_APPLIES"
    return
  fi

  printf 'unexpected kubectl call: %s\n' "$*" >&2
  return 1
}

apply_base_gateway >/dev/null
[[ "$(<"$KUBECTL_APPLIES")" == $'GatewayClass\nGateway' ]]

rm "$KUBECTL_APPLIES"
GATEWAY_CLASS_PRESENT=true
apply_base_gateway >/dev/null
[[ "$(<"$KUBECTL_APPLIES")" == "Gateway" ]]

rm "$KUBECTL_APPLIES"
GATEWAY_CLASS_PRESENT=false
GATEWAY_PRESENT=true
apply_base_gateway >/dev/null
[[ "$(<"$KUBECTL_APPLIES")" == "GatewayClass" ]]

rm "$KUBECTL_APPLIES"
GATEWAY_CLASS_PRESENT=true
apply_base_gateway >/dev/null
[[ ! -e "$KUBECTL_APPLIES" ]]

ENABLED_PROFILES=""
HELMFILE_CALLS="${TEST_ROOT}/helmfile-calls"
profile_enabled() {
  [[ " ${ENABLED_PROFILES} " == *" $1 "* ]]
}
helmfile_apply() {
  printf '%s\n' "$*" >>"$HELMFILE_CALLS"
}

apply_bootstrap_releases >/dev/null
[[ ! -e "$HELMFILE_CALLS" ]]

ENABLED_PROFILES="edge"
apply_bootstrap_releases >/dev/null
[[ "$(<"$HELMFILE_CALLS")" == "--selector profile=edge" ]]

rm "$HELMFILE_CALLS"
ENABLED_PROFILES="edge certificates"
apply_bootstrap_releases >/dev/null
[[ "$(<"$HELMFILE_CALLS")" == $'--selector profile=edge\n--selector profile=certificates' ]]

printf 'Kubernetes orchestration unit tests passed\n'
