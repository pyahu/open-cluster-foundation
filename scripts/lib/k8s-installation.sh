#!/usr/bin/env bash

set -Eeuo pipefail

INSTALLATION_STATE_NAMESPACE="platform-system"
INSTALLATION_STATE_NAME="open-cluster-foundation-installation"
INSTALLATION_STATE_SCHEMA_VERSION="1"
INSTALLATION_OPERATION_NAME="open-cluster-foundation-operation"
INSTALLATION_OPERATION_SCHEMA_VERSION="1"

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
  if kubectl -n "$INSTALLATION_STATE_NAMESPACE" get configmap "$INSTALLATION_OPERATION_NAME" >/dev/null 2>&1; then
    printf '%s\n' partial
    return
  fi

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

resolve_partial_setting() {
  local requested_value="$1"
  local recorded_value="$2"
  local option_name="$3"

  [[ -n "$recorded_value" ]] || die "partial installation operation does not contain ${option_name}"
  if [[ "$requested_value" == "auto" || "$requested_value" == "$recorded_value" ]]; then
    printf '%s\n' "$recorded_value"
    return
  fi

  die "partial installation recorded ${option_name}=${recorded_value}, but ${requested_value} was requested; resume with the recorded setting"
}

resolve_network_policy_mode() {
  local requested_mode="$1"
  local observed_state="$2"
  local managed_state="${3:-}"

  case "$requested_mode" in
    auto)
      if [[ "$observed_state" == "fresh" ]]; then
        printf '%s\n' enforce
      elif [[ "$observed_state" == "managed" && "$managed_state" == "enforced" ]]; then
        printf '%s\n' enforce
      else
        printf '%s\n' preserve
      fi
      ;;
    enforce|preserve)
      printf '%s\n' "$requested_mode"
      ;;
    *)
      die "unknown network policy mode: ${requested_mode}; expected auto, enforce or preserve"
      ;;
  esac
}

resolve_observability_scope() {
  local requested_scope="$1"
  local observed_state="$2"
  local managed_scope="${3:-}"

  case "$requested_scope" in
    auto)
      if [[ "$observed_state" == "fresh" ]]; then
        printf '%s\n' trusted
      elif [[ "$observed_state" == "managed" && "$managed_scope" == "trusted" ]]; then
        printf '%s\n' trusted
      else
        printf '%s\n' legacy
      fi
      ;;
    trusted|legacy)
      printf '%s\n' "$requested_scope"
      ;;
    *)
      die "unknown observability scope: ${requested_scope}; expected auto, trusted or legacy"
      ;;
  esac
}

resolve_identity_access_mode() {
  local requested_mode="$1"
  local observed_state="$2"
  local managed_mode="${3:-}"

  case "$requested_mode" in
    auto)
      if [[ "$observed_state" == "fresh" ]]; then
        printf '%s\n' sso
      elif [[ "$observed_state" == "managed" && "$managed_mode" == "sso" ]]; then
        printf '%s\n' sso
      else
        printf '%s\n' legacy
      fi
      ;;
    sso|legacy)
      printf '%s\n' "$requested_mode"
      ;;
    *)
      die "unknown identity access mode: ${requested_mode}; expected auto, sso or legacy"
      ;;
  esac
}

resolve_cache_access_mode() {
  local requested_mode="$1"
  local observed_state="$2"
  local managed_mode="${3:-}"

  case "$requested_mode" in
    auto)
      if [[ "$observed_state" == "fresh" ]]; then
        printf '%s\n' acl
      elif [[ "$observed_state" == "managed" && "$managed_mode" == "acl" ]]; then
        printf '%s\n' acl
      else
        printf '%s\n' legacy
      fi
      ;;
    acl|legacy)
      printf '%s\n' "$requested_mode"
      ;;
    *)
      die "unknown cache access mode: ${requested_mode}; expected auto, acl or legacy"
      ;;
  esac
}

build_observability_application_namespace_regex() {
  local namespace
  local escaped_namespace
  local namespace_regex=""

  for namespace in "$@"; do
    case "$namespace" in
      platform-system|envoy-gateway-system|cert-manager|argocd|cnpg-system|data|strimzi-system|messaging|rabbitmq-system|monitoring|identity|secrets|cache|reloader)
        continue
        ;;
    esac

    escaped_namespace="${namespace//./\\.}"
    namespace_regex="${namespace_regex:+${namespace_regex}|}${escaped_namespace}"
  done

  printf '%s\n' "${namespace_regex:-a^}"
}

observability_application_namespace_regex() {
  local namespaces=()
  local namespace

  while IFS= read -r namespace; do
    [[ -n "$namespace" ]] && namespaces+=("$namespace")
  done < <(kubectl get namespace \
    -l open-cluster-foundation.io/observability-access=true \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

  if [[ -z "${namespaces[*]-}" ]]; then
    printf '%s\n' 'a^'
    return
  fi

  build_observability_application_namespace_regex "${namespaces[@]}"
}

read_installation_configmap_value() {
  local configmap_name="$1"
  local key="$2"

  kubectl -n "$INSTALLATION_STATE_NAMESPACE" get configmap "$configmap_name" -o json |
    KEY="$key" yq -r '.data[strenv(KEY)] // ""'
}

read_installation_state_value() {
  local key="$1"

  read_installation_configmap_value "$INSTALLATION_STATE_NAME" "$key"
}

read_installation_operation_value() {
  local key="$1"

  read_installation_configmap_value "$INSTALLATION_OPERATION_NAME" "$key"
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

validate_partial_installation() {
  local operation_schema
  local recorded_environment

  operation_schema="$(read_installation_operation_value schema-version)"
  [[ "$operation_schema" == "$INSTALLATION_OPERATION_SCHEMA_VERSION" ]] || die "installation operation schema ${operation_schema:-missing} is not supported by this repository"

  recorded_environment="$(read_installation_operation_value environment)"
  [[ -f "${OCF_ROOT}/kubernetes/production-base/environments/${recorded_environment}.yaml" ]] || die "partial installation operation contains an unknown environment: ${recorded_environment:-missing}"
  if [[ "$ENVIRONMENT" != "auto" && "$ENVIRONMENT" != "$recorded_environment" ]]; then
    die "partial installation recorded environment=${recorded_environment}, but ${ENVIRONMENT} was requested; resume with the recorded environment"
  fi
  ENVIRONMENT="$recorded_environment"

  OCF_RESOLVED_INSTALL_MODE="$(resolve_partial_setting "$INSTALL_MODE" "$(read_installation_operation_value mode)" mode)"
  OCF_RESOLVED_NETWORK_POLICY_MODE="$(resolve_partial_setting "$NETWORK_POLICY_MODE" "$(read_installation_operation_value network-policy-mode)" network-policies)"
  OCF_RESOLVED_OBSERVABILITY_SCOPE="$(resolve_partial_setting "$OBSERVABILITY_SCOPE" "$(read_installation_operation_value observability-scope)" observability-scope)"
  OCF_RESOLVED_IDENTITY_ACCESS_MODE="$(resolve_partial_setting "$IDENTITY_ACCESS_MODE" "$(read_installation_operation_value identity-access)" identity-access)"
  OCF_RESOLVED_CACHE_ACCESS_MODE="$(resolve_partial_setting "$CACHE_ACCESS_MODE" "$(read_installation_operation_value cache-access)" cache-access)"

  resolve_install_mode "$OCF_RESOLVED_INSTALL_MODE" "$(read_installation_operation_value initial-state)" >/dev/null
  resolve_network_policy_mode "$OCF_RESOLVED_NETWORK_POLICY_MODE" partial >/dev/null
  resolve_observability_scope "$OCF_RESOLVED_OBSERVABILITY_SCOPE" partial >/dev/null
  resolve_identity_access_mode "$OCF_RESOLVED_IDENTITY_ACCESS_MODE" partial >/dev/null
  resolve_cache_access_mode "$OCF_RESOLVED_CACHE_ACCESS_MODE" partial >/dev/null
}

prepare_installation() {
  OCF_OBSERVED_INSTALLATION_STATE="$(detect_installation_state)"

  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "partial" ]]; then
    validate_partial_installation
  else
    prepare_new_installation_operation
  fi

  if [[ "$OCF_RESOLVED_OBSERVABILITY_SCOPE" == "trusted" && "$(installation_network_policy_state)" != "enforced" ]]; then
    die "trusted observability requires enforced NetworkPolicies; pass --network-policies enforce after completing the migration"
  fi

  export OCF_OBSERVABILITY_SCOPE="$OCF_RESOLVED_OBSERVABILITY_SCOPE"
  export OCF_IDENTITY_ACCESS_MODE="$OCF_RESOLVED_IDENTITY_ACCESS_MODE"
  export OCF_CACHE_ACCESS_MODE="$OCF_RESOLVED_CACHE_ACCESS_MODE"
  if [[ "$OCF_RESOLVED_OBSERVABILITY_SCOPE" == "trusted" ]]; then
    OCF_OBSERVABILITY_APPLICATION_NAMESPACE_REGEX="$(observability_application_namespace_regex)"
    export OCF_OBSERVABILITY_APPLICATION_NAMESPACE_REGEX
  fi

  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "managed" ]]; then
    validate_managed_installation
  fi

  log "installation mode: ${OCF_RESOLVED_INSTALL_MODE} (detected state: ${OCF_OBSERVED_INSTALLATION_STATE})"
  log "network policy mode: ${OCF_RESOLVED_NETWORK_POLICY_MODE}"
  log "observability scope: ${OCF_RESOLVED_OBSERVABILITY_SCOPE}"
  log "identity access mode: ${OCF_RESOLVED_IDENTITY_ACCESS_MODE}"
  log "cache access mode: ${OCF_RESOLVED_CACHE_ACCESS_MODE}"
  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "legacy" ]]; then
    log "existing installation will retain the current compatibility path and receive state metadata only after a successful apply"
  elif [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "partial" ]]; then
    log "resuming the recorded partial installation operation"
  fi
}

prepare_new_installation_operation() {
  local managed_network_policy_state=""
  local managed_observability_scope=""
  local managed_identity_access_mode=""
  local managed_cache_access_mode=""
  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "managed" ]]; then
    managed_network_policy_state="$(read_installation_state_value network-policies)"
    managed_observability_scope="$(read_installation_state_value observability-scope)"
    managed_identity_access_mode="$(read_installation_state_value identity-access)"
    managed_cache_access_mode="$(read_installation_state_value cache-access)"
  fi

  if [[ "$ENVIRONMENT" == "auto" ]]; then
    local managed_environment=""
    if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "managed" ]]; then
      managed_environment="$(read_installation_state_value environment)"
    fi
    ENVIRONMENT="$(resolve_default_environment "$OCF_OBSERVED_INSTALLATION_STATE" "$managed_environment")"
  fi

  OCF_RESOLVED_INSTALL_MODE="$(resolve_install_mode "$INSTALL_MODE" "$OCF_OBSERVED_INSTALLATION_STATE")"
  OCF_RESOLVED_NETWORK_POLICY_MODE="$(resolve_network_policy_mode "$NETWORK_POLICY_MODE" "$OCF_OBSERVED_INSTALLATION_STATE" "$managed_network_policy_state")"
  OCF_RESOLVED_OBSERVABILITY_SCOPE="$(resolve_observability_scope "$OBSERVABILITY_SCOPE" "$OCF_OBSERVED_INSTALLATION_STATE" "$managed_observability_scope")"
  OCF_RESOLVED_IDENTITY_ACCESS_MODE="$(resolve_identity_access_mode "$IDENTITY_ACCESS_MODE" "$OCF_OBSERVED_INSTALLATION_STATE" "$managed_identity_access_mode")"
  OCF_RESOLVED_CACHE_ACCESS_MODE="$(resolve_cache_access_mode "$CACHE_ACCESS_MODE" "$OCF_OBSERVED_INSTALLATION_STATE" "$managed_cache_access_mode")"
}

installation_observability_scope_state() {
  printf '%s\n' "$OCF_RESOLVED_OBSERVABILITY_SCOPE"
}

installation_identity_access_state() {
  printf '%s\n' "$OCF_RESOLVED_IDENTITY_ACCESS_MODE"
}

installation_cache_access_state() {
  printf '%s\n' "$OCF_RESOLVED_CACHE_ACCESS_MODE"
}

installation_network_policy_state() {
  if [[ "$OCF_RESOLVED_NETWORK_POLICY_MODE" == "enforce" ]]; then
    printf '%s\n' enforced
    return
  fi

  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "managed" ]]; then
    local existing_state
    existing_state="$(read_installation_state_value network-policies)"
    if [[ "$existing_state" == "enforced" ]]; then
      printf '%s\n' enforced
      return
    fi
  fi

  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "partial" ]]; then
    local recorded_state
    recorded_state="$(read_installation_operation_value network-policies-state)"
    [[ "$recorded_state" == "enforced" || "$recorded_state" == "unmanaged" ]] || die "partial installation operation contains an invalid network-policies-state: ${recorded_state:-missing}"
    printf '%s\n' "$recorded_state"
    return
  fi

  printf '%s\n' unmanaged
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
    partial)
      local recorded_origin
      recorded_origin="$(read_installation_operation_value origin)"
      [[ "$recorded_origin" == "fresh" || "$recorded_origin" == "adopted" ]] || die "partial installation operation contains an invalid origin: ${recorded_origin:-missing}"
      printf '%s\n' "$recorded_origin"
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

begin_installation_operation() {
  if [[ "$OCF_OBSERVED_INSTALLATION_STATE" == "partial" ]]; then
    log "using existing installation operation checkpoint"
    return
  fi

  kubectl -n "$INSTALLATION_STATE_NAMESPACE" create configmap "$INSTALLATION_OPERATION_NAME" \
    --from-literal="schema-version=${INSTALLATION_OPERATION_SCHEMA_VERSION}" \
    --from-literal="environment=${ENVIRONMENT}" \
    --from-literal="mode=${OCF_RESOLVED_INSTALL_MODE}" \
    --from-literal="origin=$(installation_origin)" \
    --from-literal="initial-state=${OCF_OBSERVED_INSTALLATION_STATE}" \
    --from-literal="source-revision=$(source_revision)" \
    --from-literal="network-policy-mode=${OCF_RESOLVED_NETWORK_POLICY_MODE}" \
    --from-literal="network-policies-state=$(installation_network_policy_state)" \
    --from-literal="observability-scope=${OCF_RESOLVED_OBSERVABILITY_SCOPE}" \
    --from-literal="identity-access=${OCF_RESOLVED_IDENTITY_ACCESS_MODE}" \
    --from-literal="cache-access=${OCF_RESOLVED_CACHE_ACCESS_MODE}" \
    --from-literal="started-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --dry-run=client -o yaml |
    yq '.metadata.labels."app.kubernetes.io/name" = "open-cluster-foundation" | .metadata.labels."app.kubernetes.io/managed-by" = "open-cluster-foundation" | .metadata.labels."open-cluster-foundation.io/state" = "operation"' |
    kubectl apply -f -

  log "recorded installation operation in ${INSTALLATION_STATE_NAMESPACE}/${INSTALLATION_OPERATION_NAME}"
}

complete_installation_operation() {
  kubectl -n "$INSTALLATION_STATE_NAMESPACE" delete configmap "$INSTALLATION_OPERATION_NAME" --ignore-not-found=true
  log "cleared installation operation checkpoint"
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
    --from-literal="network-policies=$(installation_network_policy_state)" \
    --from-literal="observability-scope=$(installation_observability_scope_state)" \
    --from-literal="identity-access=$(installation_identity_access_state)" \
    --from-literal="cache-access=$(installation_cache_access_state)" \
    --from-literal="applied-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --dry-run=client -o yaml |
    yq '.metadata.labels."app.kubernetes.io/name" = "open-cluster-foundation" | .metadata.labels."app.kubernetes.io/managed-by" = "open-cluster-foundation"' |
    kubectl apply -f -

  log "recorded installation state in ${INSTALLATION_STATE_NAMESPACE}/${INSTALLATION_STATE_NAME}"
}
