#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCF_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

source "${OCF_ROOT}/scripts/lib/common.sh"
source "${OCF_ROOT}/scripts/lib/k8s-installation.sh"

assert_output() {
  local expected="$1"
  shift

  local actual
  actual="$("$@")"
  [[ "$actual" == "$expected" ]] || die "expected '${expected}', received '${actual}' from: $*"
}

assert_fails() {
  if ("$@") >/dev/null 2>&1; then
    die "expected command to fail: $*"
  fi
}

assert_output fresh resolve_install_mode auto fresh
assert_output upgrade resolve_install_mode auto legacy
assert_output upgrade resolve_install_mode auto managed
assert_output fresh resolve_install_mode fresh fresh
assert_output upgrade resolve_install_mode upgrade legacy
assert_output upgrade resolve_install_mode upgrade managed
assert_fails resolve_install_mode fresh legacy
assert_fails resolve_install_mode fresh managed
assert_fails resolve_install_mode upgrade fresh
assert_fails resolve_install_mode invalid fresh
assert_output enforce resolve_network_policy_mode auto fresh
assert_output preserve resolve_network_policy_mode auto legacy
assert_output preserve resolve_network_policy_mode auto managed
assert_output enforce resolve_network_policy_mode auto managed enforced
assert_output enforce resolve_network_policy_mode enforce legacy
assert_output preserve resolve_network_policy_mode preserve fresh
assert_fails resolve_network_policy_mode invalid fresh
assert_output starter resolve_default_environment fresh
assert_output default resolve_default_environment legacy
assert_output production resolve_default_environment managed production
assert_fails resolve_default_environment managed
assert_fails resolve_default_environment invalid

detect_installation_state() {
  printf '%s\n' "$DETECTED_INSTALLATION_STATE"
}

INSTALL_MODE=auto
ALLOW_ENVIRONMENT_CHANGE=false
NETWORK_POLICY_MODE=auto
DETECTED_INSTALLATION_STATE=fresh
ENVIRONMENT=auto
prepare_installation >/dev/null
assert_output starter printf '%s\n' "$ENVIRONMENT"
assert_output fresh printf '%s\n' "$OCF_RESOLVED_INSTALL_MODE"
DETECTED_INSTALLATION_STATE=legacy
ENVIRONMENT=auto
prepare_installation >/dev/null
assert_output default printf '%s\n' "$ENVIRONMENT"
assert_output upgrade printf '%s\n' "$OCF_RESOLVED_INSTALL_MODE"

OCF_OBSERVED_INSTALLATION_STATE=fresh
assert_output fresh installation_origin
OCF_OBSERVED_INSTALLATION_STATE=legacy
assert_output adopted installation_origin

read_installation_state_value() {
  case "$1" in
    schema-version)
      printf '%s\n' 1
      ;;
    environment)
      printf '%s\n' default
      ;;
    origin)
      printf '%s\n' adopted
      ;;
    network-policies)
      printf '%s\n' "${MOCK_NETWORK_POLICY_STATE:-unmanaged}"
      ;;
  esac
}

ENVIRONMENT=default
ALLOW_ENVIRONMENT_CHANGE=false
validate_managed_installation
ENVIRONMENT=all-components
assert_fails validate_managed_installation
ALLOW_ENVIRONMENT_CHANGE=true
validate_managed_installation

OCF_OBSERVED_INSTALLATION_STATE=managed
OCF_RESOLVED_NETWORK_POLICY_MODE=preserve
MOCK_NETWORK_POLICY_STATE=enforced
assert_output enforced installation_network_policy_state
MOCK_NETWORK_POLICY_STATE=unmanaged
assert_output unmanaged installation_network_policy_state

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
STATE_MANIFEST="${WORK_DIR}/state.yaml"
BASE_DIR="${OCF_ROOT}/kubernetes/production-base"
ENVIRONMENT=ci
OCF_OBSERVED_INSTALLATION_STATE=fresh
OCF_RESOLVED_INSTALL_MODE=fresh
OCF_RESOLVED_NETWORK_POLICY_MODE=enforce
OCF_SOURCE_REVISION=test-revision

kubectl() {
  if [[ "$*" == "apply -f -" ]]; then
    tee "$STATE_MANIFEST" >/dev/null
    return
  fi

  command kubectl "$@"
}

record_installation_state >/dev/null
assert_output open-cluster-foundation yq -r '.metadata.labels."app.kubernetes.io/name"' "$STATE_MANIFEST"
assert_output 1 yq -r '.data."schema-version"' "$STATE_MANIFEST"
assert_output ci yq -r '.data.environment' "$STATE_MANIFEST"
assert_output fresh yq -r '.data.mode' "$STATE_MANIFEST"
assert_output fresh yq -r '.data.origin' "$STATE_MANIFEST"
assert_output test-revision yq -r '.data."source-revision"' "$STATE_MANIFEST"
assert_output true yq -r '.data.profiles | from_json | .edge' "$STATE_MANIFEST"
assert_output enforced yq -r '.data."network-policies"' "$STATE_MANIFEST"

printf '%s\n' "k8s installation state unit tests passed"
