#!/usr/bin/env bash

set -Eeuo pipefail

INSTALLATION_STATE_NAMESPACE="platform-system"
INSTALLATION_STATE_NAME="open-cluster-foundation-installation"
INSTALLATION_STATE_SCHEMA_VERSION="1"

known_installation_workload_exists() {
  local workload
  local workloads=(
    "envoy-gateway-system/envoy-gateway"
    "argocd/argocd-server"
    "cnpg-system/cloudnative-pg"
    "monitoring/grafana"
    "strimzi-system/strimzi-cluster-operator"
  )

  for workload in "${workloads[@]}"; do
    if kubectl -n "${workload%/*}" get deployment "${workload#*/}" >/dev/null 2>&1; then
      return 0
    fi
  done

  return 1
}

detect_installation_state() {
  if kubectl -n "$INSTALLATION_STATE_NAMESPACE" get configmap "$INSTALLATION_STATE_NAME" >/dev/null 2>&1; then
    printf '%s\n' managed
    return
  fi

  if known_installation_workload_exists; then
    printf '%s\n' legacy
    return
  fi

  printf '%s\n' fresh
}

resolve_default_environment() {
  local observed_state="$1"
  local managed_environment="${2:-}"

  case "$observed_state" in
    fresh)
      printf '%s\n' starter
      ;;
    legacy)
      printf '%s\n' default
      ;;
    managed)
      [[ -n "$managed_environment" ]] || die "managed installation state does not contain an environment"
      printf '%s\n' "$managed_environment"
      ;;
    *)
      die "unknown installation state: ${observed_state}"
      ;;
  esac
}

resolve_install_mode() {
  local requested_mode="$1"
  local observed_state="$2"

  case "$requested_mode" in
    auto)
      if [[ "$observed_state" == "fresh" ]]; then
        printf '%s\n' fresh
      else
        printf '%s\n' upgrade
      fi
      ;;
    fresh)
      [[ "$observed_state" == "fresh" ]] || die "fresh installation requested, but an existing ${observed_state} installation was detected"
      printf '%s\n' fresh
      ;;
    upgrade)
      [[ "$observed_state" != "fresh" ]] || die "upgrade requested, but no existing installation was detected"
      printf '%s\n' upgrade
      ;;
    *)
      die "unknown installation mode: ${requested_mode}; expected auto, fresh or upgrade"
      ;;
  esac
}

read_installation_state_value() {
  local key="$1"

  kubectl -n "$INSTALLATION_STATE_NAMESPACE" get configmap "$INSTALLATION_STATE_NAME" \
    -o "go-template={{ index .data \"${key}\" }}"
}

validate_managed_installation() {
  local existing_schema
  local existing_environment

  existing_schema="$(read_installation_state_value schema-version)"
  [[ "$existing_schema" == "$INSTALLATION_STATE_SCHEMA_VERSION" ]] || die "installation state schema ${existing_schema:-missing} is not supported by this repository"

  existing_environment="$(read_installation_state_value environment)"
  if [[ -n "$existing_environment" && "$existing_environment" != "$ENVIRONMENT" && "$ALLOW_ENVIRONMENT_CHANGE" != "true" ]]; then
    die "installation environment is ${existing_environment}, but ${ENVIRONMENT} was requested; use --allow-environment-change only after reviewing the profile changes"
  fi
}

prepare_installation() {
  OCF_OBSERVED_INSTALLATION_STATE="$(detect_installation_state)"

  if [[ "$ENVIRONMENT" == "auto" ]]; then
    local managed_environment=""
    if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "managed" ]]; then
      managed_environment="$(read_installation_state_value environment)"
    fi
    ENVIRONMENT="$(resolve_default_environment "$OCF_OBSERVED_INSTALLATION_STATE" "$managed_environment")"
  fi

  OCF_RESOLVED_INSTALL_MODE="$(resolve_install_mode "$INSTALL_MODE" "$OCF_OBSERVED_INSTALLATION_STATE")"

  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "managed" ]]; then
    validate_managed_installation
  fi

  log "installation mode: ${OCF_RESOLVED_INSTALL_MODE} (detected state: ${OCF_OBSERVED_INSTALLATION_STATE})"
  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "legacy" ]]; then
    log "existing installation will retain the current compatibility path and receive state metadata only after a successful apply"
  fi
}

installation_origin() {
  case "$OCF_OBSERVED_INSTALLATION_STATE" in
    fresh)
      printf '%s\n' fresh
      ;;
    legacy)
      printf '%s\n' adopted
      ;;
    managed)
      local origin
      origin="$(read_installation_state_value origin)"
      printf '%s\n' "${origin:-adopted}"
      ;;
  esac
}

source_revision() {
  if [[ -n "${OCF_SOURCE_REVISION:-}" ]]; then
    printf '%s\n' "$OCF_SOURCE_REVISION"
    return
  fi

  if command -v git >/dev/null 2>&1; then
    git -C "$OCF_ROOT" rev-parse --verify HEAD 2>/dev/null || printf '%s\n' unknown
    return
  fi

  printf '%s\n' unknown
}

record_installation_state() {
  local environment_file="${BASE_DIR}/environments/${ENVIRONMENT}.yaml"
  local profiles
  local versions_digest

  profiles="$(yq -o=json -I=0 '.profiles' "$environment_file")"
  versions_digest="$(openssl dgst -sha256 "${BASE_DIR}/versions.yaml" | awk '{print $NF}')"

  kubectl -n "$INSTALLATION_STATE_NAMESPACE" create configmap "$INSTALLATION_STATE_NAME" \
    --from-literal="schema-version=${INSTALLATION_STATE_SCHEMA_VERSION}" \
    --from-literal="environment=${ENVIRONMENT}" \
    --from-literal="mode=${OCF_RESOLVED_INSTALL_MODE}" \
    --from-literal="origin=$(installation_origin)" \
    --from-literal="source-revision=$(source_revision)" \
    --from-literal="versions-sha256=${versions_digest}" \
    --from-literal="profiles=${profiles}" \
    --from-literal="applied-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --dry-run=client -o yaml |
    yq '.metadata.labels."app.kubernetes.io/name" = "open-cluster-foundation" | .metadata.labels."app.kubernetes.io/managed-by" = "open-cluster-foundation"' |
    kubectl apply -f -

  log "recorded installation state in ${INSTALLATION_STATE_NAMESPACE}/${INSTALLATION_STATE_NAME}"
}
