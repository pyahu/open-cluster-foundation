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
assert_output trusted resolve_observability_scope auto fresh
assert_output legacy resolve_observability_scope auto legacy
assert_output legacy resolve_observability_scope auto managed
assert_output trusted resolve_observability_scope auto managed trusted
assert_output trusted resolve_observability_scope trusted legacy
assert_output legacy resolve_observability_scope legacy fresh
assert_fails resolve_observability_scope invalid fresh
assert_output sso resolve_identity_access_mode auto fresh
assert_output legacy resolve_identity_access_mode auto legacy
assert_output legacy resolve_identity_access_mode auto managed
assert_output sso resolve_identity_access_mode auto managed sso
assert_output sso resolve_identity_access_mode sso legacy
assert_output legacy resolve_identity_access_mode legacy fresh
assert_fails resolve_identity_access_mode invalid fresh
assert_output acl resolve_cache_access_mode auto fresh
assert_output legacy resolve_cache_access_mode auto legacy
assert_output legacy resolve_cache_access_mode auto managed
assert_output acl resolve_cache_access_mode auto managed acl
assert_output acl resolve_cache_access_mode acl legacy
assert_output legacy resolve_cache_access_mode legacy fresh
assert_fails resolve_cache_access_mode invalid fresh
assert_output 'team-a|team-b' build_observability_application_namespace_regex platform-system team-a monitoring team-b
assert_output 'a^' build_observability_application_namespace_regex platform-system monitoring

KUBECTL_INSTALLATION_STATE=fresh
kubectl() {
  case "$*" in
    "-n platform-system get configmap open-cluster-foundation-operation")
      [[ "$KUBECTL_INSTALLATION_STATE" == "partial" ]]
      ;;
    "-n platform-system get configmap open-cluster-foundation-installation")
      [[ "$KUBECTL_INSTALLATION_STATE" == "managed" ]]
      ;;
    *" get deployment "*)
      [[ "$KUBECTL_INSTALLATION_STATE" == "legacy" ]]
      ;;
    *)
      return 0
      ;;
  esac
}
kubectl >/dev/null
assert_output 'a^' observability_application_namespace_regex
assert_output fresh detect_installation_state
KUBECTL_INSTALLATION_STATE=legacy
assert_output legacy detect_installation_state
KUBECTL_INSTALLATION_STATE=managed
assert_output managed detect_installation_state
KUBECTL_INSTALLATION_STATE=partial
assert_output partial detect_installation_state
unset -f kubectl

kubectl() {
  printf '%s\n' '{"data":{"schema-version":"1","environment":"production"}}'
}
kubectl >/dev/null
assert_output 1 read_installation_configmap_value example schema-version
assert_output production read_installation_configmap_value example environment
assert_output '' read_installation_configmap_value example missing
unset -f kubectl

assert_output starter resolve_default_environment fresh
assert_output default resolve_default_environment legacy
assert_output production resolve_default_environment managed production
assert_fails resolve_default_environment managed
assert_fails resolve_default_environment invalid

detect_installation_state() {
  printf '%s\n' "$DETECTED_INSTALLATION_STATE"
}

observability_application_namespace_regex() {
  printf '%s\n' 'a^'
}

INSTALL_MODE=auto
ALLOW_ENVIRONMENT_CHANGE=false
NETWORK_POLICY_MODE=auto
OBSERVABILITY_SCOPE=auto
IDENTITY_ACCESS_MODE=auto
CACHE_ACCESS_MODE=auto
DETECTED_INSTALLATION_STATE=fresh
ENVIRONMENT=auto
prepare_installation >/dev/null
assert_output starter printf '%s\n' "$ENVIRONMENT"
assert_output fresh printf '%s\n' "$OCF_RESOLVED_INSTALL_MODE"
assert_output sso printf '%s\n' "$OCF_RESOLVED_IDENTITY_ACCESS_MODE"
assert_output acl printf '%s\n' "$OCF_RESOLVED_CACHE_ACCESS_MODE"
DETECTED_INSTALLATION_STATE=legacy
ENVIRONMENT=auto
prepare_installation >/dev/null
assert_output default printf '%s\n' "$ENVIRONMENT"
assert_output upgrade printf '%s\n' "$OCF_RESOLVED_INSTALL_MODE"
assert_output legacy printf '%s\n' "$OCF_RESOLVED_OBSERVABILITY_SCOPE"
assert_output legacy printf '%s\n' "$OCF_RESOLVED_IDENTITY_ACCESS_MODE"
assert_output legacy printf '%s\n' "$OCF_RESOLVED_CACHE_ACCESS_MODE"

DETECTED_INSTALLATION_STATE=legacy
ENVIRONMENT=auto
NETWORK_POLICY_MODE=auto
OBSERVABILITY_SCOPE=trusted
assert_fails prepare_installation

ENVIRONMENT=auto
NETWORK_POLICY_MODE=enforce
prepare_installation >/dev/null
assert_output trusted printf '%s\n' "$OCF_RESOLVED_OBSERVABILITY_SCOPE"
assert_output trusted printf '%s\n' "$OCF_OBSERVABILITY_SCOPE"
OBSERVABILITY_SCOPE=auto
NETWORK_POLICY_MODE=auto

read_installation_operation_value() {
  case "$1" in
    schema-version)
      printf '%s\n' 1
      ;;
    environment)
      printf '%s\n' production
      ;;
    mode)
      printf '%s\n' upgrade
      ;;
    initial-state)
      printf '%s\n' managed
      ;;
    origin)
      printf '%s\n' adopted
      ;;
    network-policy-mode)
      printf '%s\n' enforce
      ;;
    network-policies-state)
      printf '%s\n' enforced
      ;;
    observability-scope)
      printf '%s\n' trusted
      ;;
    identity-access)
      printf '%s\n' sso
      ;;
    cache-access)
      printf '%s\n' acl
      ;;
  esac
}

DETECTED_INSTALLATION_STATE=partial
ENVIRONMENT=auto
INSTALL_MODE=auto
NETWORK_POLICY_MODE=auto
OBSERVABILITY_SCOPE=auto
IDENTITY_ACCESS_MODE=auto
CACHE_ACCESS_MODE=auto
prepare_installation >/dev/null
assert_output production printf '%s\n' "$ENVIRONMENT"
assert_output upgrade printf '%s\n' "$OCF_RESOLVED_INSTALL_MODE"
assert_output enforce printf '%s\n' "$OCF_RESOLVED_NETWORK_POLICY_MODE"
assert_output trusted printf '%s\n' "$OCF_RESOLVED_OBSERVABILITY_SCOPE"
assert_output adopted installation_origin
assert_output enforced installation_network_policy_state

ENVIRONMENT=starter
assert_fails prepare_installation
ENVIRONMENT=auto
NETWORK_POLICY_MODE=preserve
assert_fails prepare_installation
NETWORK_POLICY_MODE=auto

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
    observability-scope)
      printf '%s\n' "${MOCK_OBSERVABILITY_SCOPE:-legacy}"
      ;;
    identity-access)
      printf '%s\n' "${MOCK_IDENTITY_ACCESS_MODE:-legacy}"
      ;;
    cache-access)
      printf '%s\n' "${MOCK_CACHE_ACCESS_MODE:-legacy}"
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
OPERATION_MANIFEST="${WORK_DIR}/operation.yaml"
KUBECTL_MUTATIONS="${WORK_DIR}/kubectl-mutations"
BASE_DIR="${OCF_ROOT}/kubernetes/production-base"
ENVIRONMENT=ci
OCF_OBSERVED_INSTALLATION_STATE=fresh
OCF_RESOLVED_INSTALL_MODE=fresh
OCF_RESOLVED_NETWORK_POLICY_MODE=enforce
OCF_RESOLVED_OBSERVABILITY_SCOPE=trusted
OCF_RESOLVED_IDENTITY_ACCESS_MODE=sso
OCF_RESOLVED_CACHE_ACCESS_MODE=acl
OCF_SOURCE_REVISION=test-revision

kubectl() {
  if [[ "$*" == "apply -f -" ]]; then
    local manifest
    manifest="$(cat)"
    if [[ "$(yq -r '.metadata.name' <<<"$manifest")" == "$INSTALLATION_OPERATION_NAME" ]]; then
      printf '%s\n' "$manifest" >"$OPERATION_MANIFEST"
    else
      printf '%s\n' "$manifest" >"$STATE_MANIFEST"
    fi
    return
  fi

  if [[ "$*" == "-n platform-system delete configmap open-cluster-foundation-operation --ignore-not-found=true" ]]; then
    printf '%s\n' "$*" >>"$KUBECTL_MUTATIONS"
    return
  fi

  command kubectl "$@"
}

begin_installation_operation >/dev/null
assert_output ci yq -r '.data.environment' "$OPERATION_MANIFEST"
assert_output fresh yq -r '.data.mode' "$OPERATION_MANIFEST"
assert_output fresh yq -r '.data."initial-state"' "$OPERATION_MANIFEST"
assert_output enforced yq -r '.data."network-policies-state"' "$OPERATION_MANIFEST"
assert_output operation yq -r '.metadata.labels."open-cluster-foundation.io/state"' "$OPERATION_MANIFEST"

record_installation_state >/dev/null
assert_output open-cluster-foundation yq -r '.metadata.labels."app.kubernetes.io/name"' "$STATE_MANIFEST"
assert_output 1 yq -r '.data."schema-version"' "$STATE_MANIFEST"
assert_output ci yq -r '.data.environment' "$STATE_MANIFEST"
assert_output fresh yq -r '.data.mode' "$STATE_MANIFEST"
assert_output fresh yq -r '.data.origin' "$STATE_MANIFEST"
assert_output test-revision yq -r '.data."source-revision"' "$STATE_MANIFEST"
assert_output true yq -r '.data.profiles | from_json | .edge' "$STATE_MANIFEST"
assert_output enforced yq -r '.data."network-policies"' "$STATE_MANIFEST"
assert_output trusted yq -r '.data."observability-scope"' "$STATE_MANIFEST"
assert_output sso yq -r '.data."identity-access"' "$STATE_MANIFEST"
assert_output acl yq -r '.data."cache-access"' "$STATE_MANIFEST"

complete_installation_operation >/dev/null
assert_output '-n platform-system delete configmap open-cluster-foundation-operation --ignore-not-found=true' cat "$KUBECTL_MUTATIONS"

printf '%s\n' "k8s installation state unit tests passed"
