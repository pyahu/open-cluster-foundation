#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/k8s-config.sh
source "${SCRIPT_DIR}/lib/k8s-config.sh"
# shellcheck source=lib/k8s-installation.sh
source "${SCRIPT_DIR}/lib/k8s-installation.sh"
# shellcheck source=lib/k8s-secrets.sh
source "${SCRIPT_DIR}/lib/k8s-secrets.sh"

ACTION="${1:-check}"
shift || true

ENVIRONMENT="${OCF_K8S_ENVIRONMENT:-auto}"
AUTO_APPROVE="${OCF_AUTO_APPROVE:-false}"
INSTALL_MODE="${OCF_INSTALL_MODE:-auto}"
ALLOW_ENVIRONMENT_CHANGE="${OCF_ALLOW_ENVIRONMENT_CHANGE:-false}"
NETWORK_POLICY_MODE="${OCF_NETWORK_POLICY_MODE:-auto}"
OBSERVABILITY_SCOPE="${OCF_OBSERVABILITY_SCOPE:-auto}"
IDENTITY_ACCESS_MODE="${OCF_IDENTITY_ACCESS_MODE:-auto}"
CACHE_ACCESS_MODE="${OCF_CACHE_ACCESS_MODE:-auto}"
GRAFANA_DATABASE_CIDRS="${OCF_GRAFANA_DATABASE_CIDRS:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/k8s-production-base.sh check [--mode auto|fresh|upgrade] [--network-policies auto|enforce|preserve] [--observability-scope auto|trusted|legacy] [--identity-access auto|sso|legacy] [--cache-access auto|acl|legacy]
  scripts/k8s-production-base.sh render [--environment starter|production|production-ha|production-data|default|all-components] [--network-policies auto|enforce|preserve] [--observability-scope auto|trusted|legacy] [--identity-access auto|sso|legacy] [--cache-access auto|acl|legacy]
  scripts/k8s-production-base.sh apply [--environment starter|production|production-ha|production-data|default|all-components] [--mode auto|fresh|upgrade] [--network-policies auto|enforce|preserve] [--observability-scope auto|trusted|legacy] [--identity-access auto|sso|legacy] [--cache-access auto|acl|legacy] [--allow-environment-change] [--yes]

Environment:
  ACME_EMAIL              Optional. If set, Let's Encrypt issuers are created with this email.
  OCF_AUTO_APPROVE=true   Skip interactive confirmation for apply.
  OCF_K8S_ENVIRONMENT     Helmfile environment. Defaults to automatic selection.
  OCF_INSTALL_MODE        Installation mode. Defaults to "auto".
  OCF_NETWORK_POLICY_MODE Network policy mode. Defaults to "auto".
  OCF_OBSERVABILITY_SCOPE Observability discovery scope. Defaults to "auto".
  OCF_IDENTITY_ACCESS_MODE Identity access mode. Defaults to "auto".
  OCF_CACHE_ACCESS_MODE   Cache access mode. Defaults to "auto".
  OCF_GRAFANA_DATABASE_CIDRS
                          Comma-separated PostgreSQL CIDRs required by production-ha.
  OCF_ALLOW_ENVIRONMENT_CHANGE=true
                          Allow a managed installation to change environment.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment)
      ENVIRONMENT="${2:-}"
      [[ -n "$ENVIRONMENT" ]] || die "--environment requires a value"
      shift
      ;;
    --yes)
      AUTO_APPROVE="true"
      ;;
    --mode)
      INSTALL_MODE="${2:-}"
      [[ -n "$INSTALL_MODE" ]] || die "--mode requires a value"
      shift
      ;;
    --network-policies)
      NETWORK_POLICY_MODE="${2:-}"
      [[ -n "$NETWORK_POLICY_MODE" ]] || die "--network-policies requires a value"
      shift
      ;;
    --observability-scope)
      OBSERVABILITY_SCOPE="${2:-}"
      [[ -n "$OBSERVABILITY_SCOPE" ]] || die "--observability-scope requires a value"
      shift
      ;;
    --identity-access)
      IDENTITY_ACCESS_MODE="${2:-}"
      [[ -n "$IDENTITY_ACCESS_MODE" ]] || die "--identity-access requires a value"
      shift
      ;;
    --cache-access)
      CACHE_ACCESS_MODE="${2:-}"
      [[ -n "$CACHE_ACCESS_MODE" ]] || die "--cache-access requires a value"
      shift
      ;;
    --allow-environment-change)
      ALLOW_ENVIRONMENT_CHANGE="true"
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

BASE_DIR="${OCF_ROOT}/kubernetes/production-base"
HELMFILE_APPLY_ARGS=()
if [[ "${OCF_HELMFILE_SUPPRESS_DIFF:-false}" == "true" ]]; then
  HELMFILE_APPLY_ARGS+=(--suppress-diff)
fi

# The e2e suite swaps the production Kafka resources for CI-sized ones.
KAFKA_CLUSTER_FILE="${OCF_KAFKA_CLUSTER_FILE:-${BASE_DIR}/resources/kafka/kafka-cluster.yaml}"
KAFKA_CONNECT_FILE="${OCF_KAFKA_CONNECT_FILE:-${BASE_DIR}/resources/kafka/kafka-connect.yaml}"

require_k8s_tools() {
  local helm_diff_version

  require_command kubectl
  require_command helm
  require_command helmfile
  require_command kustomize
  require_command openssl
  require_command yq

  helm_diff_version="$(component_value helmDiff version)"
  helm_diff_version="${helm_diff_version#v}"
  [[ "$(helm plugin list 2>/dev/null | awk '$1 == "diff" { print $2 }')" == "$helm_diff_version" ]] ||
    die "helm diff plugin ${helm_diff_version} is required"
}

apply_verified_manifest() {
  local component="$1"
  local manifest_url
  local manifest_sha256
  local manifest_file
  local apply_status

  manifest_url="$(component_value "$component" manifest)"
  manifest_sha256="$(component_value "$component" manifestSha256)"
  [[ -n "$manifest_url" ]] || die "could not read ${component} manifest from versions.yaml"
  [[ -n "$manifest_sha256" ]] || die "could not read ${component} manifest checksum from versions.yaml"

  manifest_file="$(mktemp)"
  download_verified "$manifest_url" "$manifest_sha256" "$manifest_file"
  apply_status=0
  kubectl apply --server-side --force-conflicts -f "$manifest_file" || apply_status=$?
  rm -f "$manifest_file"
  return "$apply_status"
}

check_default_storage_class() {
  local default_storage_class
  default_storage_class="$(
    kubectl get storageclass \
      -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  [[ -n "$default_storage_class" ]] || die "no default StorageClass found"
  log "default StorageClass: ${default_storage_class//$'\n'/, }"
}

preflight() {
  require_command kubectl

  log "checking current Kubernetes context"
  kubectl config current-context
  kubectl cluster-info
  kubectl get nodes -o wide
  check_default_storage_class
  kubectl auth can-i '*' '*' --all-namespaces >/dev/null || die "current identity does not have cluster-admin-like permissions"
}

check_high_availability_topology() {
  if ! profile_enabled highAvailability "$ENVIRONMENT"; then
    return
  fi

  validate_high_availability_topology_json "$(kubectl get nodes -o json)"
}

check_configuration() {
  require_command kubectl
  require_command yq
  preflight
  prepare_installation
  validate_profile_contract
  if profile_enabled highAvailability "$ENVIRONMENT"; then
    validate_grafana_database_cidrs
  fi
  check_high_availability_topology
  validate_instance_values
  check_optional_profile_inputs
  check_identity_inputs
}

create_grafana_admin_secret() {
  if ! profile_enabled observability "$ENVIRONMENT"; then
    return
  fi

  if kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
    log "Grafana admin secret already exists"
    return
  fi

  log "creating Grafana admin secret"
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal="admin-password=$(openssl rand -base64 32)"
}

apply_cluster_issuers_if_configured() {
  if ! profile_enabled certificates "$ENVIRONMENT"; then
    return
  fi

  if [[ -z "${ACME_EMAIL:-}" ]]; then
    warn "ACME_EMAIL is not set; skipping Let's Encrypt ClusterIssuers"
    return
  fi

  log "applying Let's Encrypt ClusterIssuers for ${ACME_EMAIL}"
  sed "s/platform@example.com/${ACME_EMAIL}/g" "${BASE_DIR}/resources/cert-manager/cluster-issuers.yaml" |
    kubectl apply -f -
}

apply_rabbitmq_operators() {
  if ! profile_enabled rabbitmqOperators "$ENVIRONMENT"; then
    log "skipping RabbitMQ operators (profile disabled)"
    return
  fi

  log "applying RabbitMQ operators"
  apply_verified_manifest rabbitmqClusterOperator
  apply_verified_manifest rabbitmqMessagingTopologyOperator
}

apply_base_gateway() {
  if ! profile_enabled edge "$ENVIRONMENT"; then
    return
  fi

  # manifests/gateway.yaml is a bootstrap placeholder: a GatewayClass without
  # parametersRef and a single HTTP listener. Real instances customise both
  # (HTTPS listeners per hostname and an EnvoyProxy carrying the provider's
  # load balancer annotations), and re-applying the placeholder on top undoes
  # that: the data plane Service loses its annotations, the cloud controller
  # creates a new load balancer (with a new IP!) and every HTTPS host goes
  # down because DNS still points at the old one. That happened on a
  # production cluster on 2026-08-10.
  #
  # So the gateway is only created when missing. To re-apply the placeholder
  # on purpose, set OCF_FORCE_BASE_GATEWAY=true, then re-apply the instance
  # customisation.
  if [[ "${OCF_FORCE_BASE_GATEWAY:-false}" == "true" ]]; then
    log "applying base Gateway (forced; instance customisations will be overwritten)"
    kubectl apply -f "${BASE_DIR}/manifests/gateway.yaml"
    return
  fi

  # The checks must live inside an "if": under "set -e" a "cmd && action"
  # list aborts the script when cmd fails, and failing is the normal case
  # here (a fresh cluster has no Gateway yet).
  local existing=()
  if kubectl get gatewayclass envoy >/dev/null 2>&1; then
    existing+=("GatewayClass/envoy")
  fi
  if kubectl -n platform-system get gateway public-gateway >/dev/null 2>&1; then
    existing+=("Gateway/public-gateway")
  fi

  if [[ "${#existing[@]}" -gt 0 ]]; then
    log "base Gateway already present (${existing[*]}); keeping instance customisations"
    log "  re-apply the placeholder with OCF_FORCE_BASE_GATEWAY=true if you really want it"
    return
  fi

  log "applying base Gateway"
  kubectl apply -f "${BASE_DIR}/manifests/gateway.yaml"
}

apply_prometheus_operator_crds() {
  if ! profile_enabled observability "$ENVIRONMENT"; then
    return
  fi

  log "applying Prometheus Operator CRDs"
  apply_verified_manifest prometheusOperatorCrds
}

apply_plugin_barman_cloud() {
  if ! profile_enabled postgresOperator "$ENVIRONMENT"; then
    return
  fi

  log "applying CloudNativePG Barman Cloud plugin"
  apply_verified_manifest pluginBarmanCloud
}

apply_monitoring_resources() {
  if ! profile_enabled observability "$ENVIRONMENT"; then
    return
  fi

  log "applying Prometheus rules and pod monitors"
  kubectl apply -f "${BASE_DIR}/resources/monitoring/"
}

render() {
  require_k8s_tools

  if [[ "$ENVIRONMENT" == "auto" ]]; then
    ENVIRONMENT="starter"
  fi

  validate_profile_contract
  if profile_enabled highAvailability "$ENVIRONMENT"; then
    validate_grafana_database_cidrs
  fi

  local render_file="/tmp/open-cluster-foundation-${ENVIRONMENT}.yaml"
  local render_network_policy_mode
  local render_observability_scope
  local render_identity_access_mode
  local render_cache_access_mode
  local require_observability_identity="true"
  local network_policy_values=()
  render_network_policy_mode="$(resolve_network_policy_mode "$NETWORK_POLICY_MODE" fresh)"
  render_observability_scope="$(resolve_observability_scope "$OBSERVABILITY_SCOPE" fresh)"
  render_identity_access_mode="$(resolve_identity_access_mode "$IDENTITY_ACCESS_MODE" fresh)"
  render_cache_access_mode="$(resolve_cache_access_mode "$CACHE_ACCESS_MODE" fresh)"
  if [[ "$render_observability_scope" == "trusted" && "$render_network_policy_mode" != "enforce" ]]; then
    die "trusted observability requires enforced NetworkPolicies"
  fi
  export OCF_OBSERVABILITY_SCOPE="$render_observability_scope"
  export OCF_IDENTITY_ACCESS_MODE="$render_identity_access_mode"
  export OCF_CACHE_ACCESS_MODE="$render_cache_access_mode"
  if [[ "$render_observability_scope" == "trusted" ]]; then
    export OCF_OBSERVABILITY_APPLICATION_NAMESPACE_REGEX="${OCF_OBSERVABILITY_APPLICATION_NAMESPACE_REGEX:-a^}"
  fi
  if [[ "$render_observability_scope" == "legacy" ]]; then
    require_observability_identity="false"
  fi
  network_policy_values+=(--set "observability.requireWorkloadIdentity=${require_observability_identity}")
  if profile_enabled highAvailability "$ENVIRONMENT"; then
    network_policy_values+=(--set "grafanaDatabaseCidrs={${GRAFANA_DATABASE_CIDRS}}")
  fi

  log "rendering helmfile environment ${ENVIRONMENT}"
  {
    printf '%s\n' "---"
    cat "${BASE_DIR}/manifests/namespace-baseline.yaml"
    printf '%s\n' "---"
    (cd "$BASE_DIR" && helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" template)
    if profile_enabled edge "$ENVIRONMENT"; then
      printf '%s\n' "---"
      cat "${BASE_DIR}/manifests/gateway.yaml"
    fi
    if profile_enabled observability "$ENVIRONMENT"; then
      printf '%s\n' "---"
      cat "${BASE_DIR}"/resources/monitoring/*.yaml
    fi
    if profile_enabled kafka "$ENVIRONMENT"; then
      printf '%s\n' "---"
      cat "${BASE_DIR}/resources/kafka/kafka-cluster.yaml"
    fi
    if profile_enabled kafkaConnect "$ENVIRONMENT"; then
      printf '%s\n' "---"
      cat "${BASE_DIR}/resources/kafka/kafka-connect.yaml"
    fi
    if [[ "$render_network_policy_mode" == "enforce" ]]; then
      printf '%s\n' "---"
      helm template ocf-network-policies "${BASE_DIR}/charts/network-policies" \
        --namespace platform-system \
        "${network_policy_values[@]}"
    fi
  } >"$render_file"
  log "rendered manifest written to ${render_file}"
}

wait_for_controllers() {
  if profile_enabled certificates "$ENVIRONMENT"; then
    kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
    kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
  fi
  if profile_enabled edge "$ENVIRONMENT"; then
    kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s
  fi
  if profile_enabled gitops "$ENVIRONMENT"; then
    kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
  fi
  if profile_enabled postgresOperator "$ENVIRONMENT"; then
    kubectl -n cnpg-system rollout status deploy/cloudnative-pg --timeout=180s
    kubectl -n cnpg-system rollout status deploy/barman-cloud --timeout=180s
  fi
  if profile_enabled messagingOperators "$ENVIRONMENT"; then
    kubectl -n strimzi-system rollout status deploy/strimzi-cluster-operator --timeout=180s
  fi
  if profile_enabled rabbitmqOperators "$ENVIRONMENT"; then
    kubectl -n rabbitmq-system wait --for=condition=Available deployment --all --timeout=300s
  fi
  if profile_enabled identity "$ENVIRONMENT"; then
    kubectl -n identity rollout status deploy/zitadel --timeout=300s
    kubectl -n identity rollout status deploy/zitadel-login --timeout=300s
  fi
  if profile_enabled secrets "$ENVIRONMENT"; then
    kubectl -n secrets rollout status deploy/infisical-infisical-standalone-infisical --timeout=300s
  fi
  kubectl -n reloader wait --for=condition=Available deployment --all --timeout=180s
}

apply_kafka_base() {
  if ! profile_enabled kafka "$ENVIRONMENT"; then
    log "skipping Kafka cluster (profile disabled)"
    return
  fi

  log "applying base Kafka cluster"
  kubectl apply -f "$KAFKA_CLUSTER_FILE"
  kubectl -n messaging wait --for=condition=Ready kafka/foundation-kafka --timeout=1200s

  if ! profile_enabled kafkaConnect "$ENVIRONMENT"; then
    log "skipping Kafka Connect (profile disabled)"
    return
  fi

  log "applying base Kafka Connect cluster"
  kubectl apply -f "$KAFKA_CONNECT_FILE"
  kubectl -n messaging wait --for=condition=Ready kafkaconnect/foundation-connect --timeout=900s
}

apply_network_policies() {
  if [[ "$OCF_RESOLVED_NETWORK_POLICY_MODE" != "enforce" ]]; then
    log "preserving current NetworkPolicy state"
    return
  fi

  log "enforcing the base namespace NetworkPolicies"
  local require_observability_identity="true"
  local network_policy_values=()
  if [[ "$OCF_RESOLVED_OBSERVABILITY_SCOPE" == "legacy" ]]; then
    require_observability_identity="false"
  fi
  network_policy_values+=(--set "observability.requireWorkloadIdentity=${require_observability_identity}")
  if profile_enabled highAvailability "$ENVIRONMENT"; then
    network_policy_values+=(--set "grafanaDatabaseCidrs={${GRAFANA_DATABASE_CIDRS}}")
  fi
  helm upgrade --install ocf-network-policies "${BASE_DIR}/charts/network-policies" \
    --namespace platform-system \
    "${network_policy_values[@]}" \
    --atomic \
    --wait \
    --timeout 5m
}

helmfile_apply() {
  (cd "$BASE_DIR" && helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" apply "${HELMFILE_APPLY_ARGS[@]}" "$@")
}

apply_base() {
  require_k8s_tools
  check_configuration
  confirm_apply "This will install or update the Kubernetes production base on the current context" "$AUTO_APPROVE"

  log "applying namespaces and Pod Security labels"
  kubectl apply -f "${BASE_DIR}/manifests/namespace-baseline.yaml"

  prepare_valkey_acl_secret
  apply_prometheus_operator_crds

  # Envoy Gateway ships (and owns) the Gateway API CRDs, which cert-manager's
  # Gateway integration requires at startup; cert-manager must exist before
  # the RabbitMQ topology operator, which uses its webhook certificates.
  log "installing Envoy Gateway first"
  helmfile_apply --selector profile=edge

  log "installing cert-manager"
  helmfile_apply --selector profile=certificates

  apply_cluster_issuers_if_configured
  apply_rabbitmq_operators
  apply_plugin_barman_cloud
  create_grafana_admin_secret

  # Concurrency is bounded so a fresh cluster is not saturated by a dozen
  # simultaneous installs: unbounded concurrency starves operator liveness
  # probes on small nodes and helm rolls healthy releases back.
  log "applying helmfile environment ${ENVIRONMENT}"
  helmfile_apply --concurrency 4

  apply_base_gateway

  apply_monitoring_resources

  wait_for_controllers
  apply_kafka_base
  apply_network_policies
  record_installation_state
}

case "$ACTION" in
  check)
    check_configuration
    ;;
  render)
    render
    ;;
  apply)
    apply_base
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage
    die "unknown action: ${ACTION}"
    ;;
esac
