#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-check}"
shift || true

ENVIRONMENT="${OCF_K8S_ENVIRONMENT:-default}"
AUTO_APPROVE="${OCF_AUTO_APPROVE:-false}"

usage() {
  cat <<'EOF'
Usage:
  scripts/k8s-production-base.sh check
  scripts/k8s-production-base.sh render [--environment default|all-components]
  scripts/k8s-production-base.sh apply [--environment default|all-components] [--yes]

Environment:
  ACME_EMAIL              Optional. If set, Let's Encrypt issuers are created with this email.
  OCF_AUTO_APPROVE=true   Skip interactive confirmation for apply.
  OCF_K8S_ENVIRONMENT     Helmfile environment. Defaults to "default".
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

require_k8s_tools() {
  require_command kubectl
  require_command helm
  require_command helmfile
  require_command openssl
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

ensure_secret_exists() {
  local namespace="$1"
  local name="$2"
  local help_text="$3"

  kubectl -n "$namespace" get secret "$name" >/dev/null 2>&1 || die "missing secret ${namespace}/${name}. ${help_text}"
}

ensure_secret_key_exists() {
  local namespace="$1"
  local name="$2"
  local key="$3"
  local help_text="$4"

  local value
  value="$(kubectl -n "$namespace" get secret "$name" -o jsonpath="{.data.${key}}" 2>/dev/null || true)"
  [[ -n "$value" ]] || die "secret ${namespace}/${name} is missing key ${key}. ${help_text}"
}

check_optional_profile_inputs() {
  if [[ "$ENVIRONMENT" != "all-components" ]]; then
    return
  fi

  ensure_secret_exists identity zitadel-masterkey "Create it before enabling the identity profile."
  ensure_secret_exists identity zitadel-postgres-dsn "Create it before enabling the identity profile."
  ensure_secret_exists secrets infisical-secrets "Create it before enabling the secrets profile."
  ensure_secret_exists secrets infisical-postgres "Create it before enabling the secrets profile."
  ensure_secret_key_exists secrets infisical-secrets REDIS_URL "Infisical requires a Redis-compatible store; point REDIS_URL at the base Valkey service (redis://valkey.cache.svc.cluster.local:6379)."
}

create_grafana_admin_secret() {
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
  if [[ -z "${ACME_EMAIL:-}" ]]; then
    warn "ACME_EMAIL is not set; skipping Let's Encrypt ClusterIssuers"
    return
  fi

  log "applying Let's Encrypt ClusterIssuers for ${ACME_EMAIL}"
  sed "s/platform@example.com/${ACME_EMAIL}/g" "${BASE_DIR}/resources/cert-manager/cluster-issuers.yaml" |
    kubectl apply -f -
}

apply_rabbitmq_operators() {
  local cluster_operator_manifest topology_operator_manifest
  cluster_operator_manifest="$(component_value rabbitmqClusterOperator manifest)"
  topology_operator_manifest="$(component_value rabbitmqMessagingTopologyOperator manifest)"

  [[ -n "$cluster_operator_manifest" ]] || die "could not read RabbitMQ Cluster Operator manifest from versions.yaml"
  [[ -n "$topology_operator_manifest" ]] || die "could not read RabbitMQ Topology Operator manifest from versions.yaml"

  log "applying RabbitMQ operators"
  kubectl apply --server-side -f "$cluster_operator_manifest"
  kubectl apply --server-side -f "$topology_operator_manifest"
}

apply_gateway_api() {
  local gateway_api_manifest
  gateway_api_manifest="$(component_value gatewayApi standardManifest)"

  [[ -n "$gateway_api_manifest" ]] || die "could not read Gateway API manifest from versions.yaml"

  log "applying Gateway API CRDs"
  kubectl apply --server-side -f "$gateway_api_manifest"
}

apply_plugin_barman_cloud() {
  local plugin_manifest
  plugin_manifest="$(component_value pluginBarmanCloud manifest)"

  [[ -n "$plugin_manifest" ]] || die "could not read plugin-barman-cloud manifest from versions.yaml"

  log "applying CloudNativePG Barman Cloud plugin"
  kubectl apply --server-side -f "$plugin_manifest"
}

apply_monitoring_resources() {
  log "applying Prometheus rules and pod monitors"
  kubectl apply -f "${BASE_DIR}/resources/monitoring/"
}

render() {
  require_k8s_tools
  local render_file="/tmp/open-cluster-foundation-${ENVIRONMENT}.yaml"

  log "rendering helmfile environment ${ENVIRONMENT}"
  {
    printf '%s\n' "---"
    cat "${BASE_DIR}/manifests/namespace-baseline.yaml"
    printf '%s\n' "---"
    (cd "$BASE_DIR" && helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" template)
    printf '%s\n' "---"
    cat "${BASE_DIR}/manifests/gateway.yaml"
    printf '%s\n' "---"
    cat "${BASE_DIR}"/resources/monitoring/*.yaml
    printf '%s\n' "---"
    cat "${BASE_DIR}/resources/kafka/kafka-cluster.yaml"
    printf '%s\n' "---"
    cat "${BASE_DIR}/resources/kafka/kafka-connect.yaml"
  } >"$render_file"
  log "rendered manifest written to ${render_file}"
}

wait_for_controllers() {
  kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
  kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
  kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s
  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
  kubectl -n cnpg-system rollout status deploy/cnpg-controller-manager --timeout=180s
  kubectl -n cnpg-system rollout status deploy/barman-cloud --timeout=180s
  kubectl -n strimzi-system rollout status deploy/strimzi-cluster-operator --timeout=180s
  kubectl -n rabbitmq-system wait --for=condition=Available deployment --all --timeout=300s
  kubectl -n reloader wait --for=condition=Available deployment --all --timeout=180s
}

apply_kafka_base() {
  log "applying base Kafka cluster"
  kubectl apply -f "${BASE_DIR}/resources/kafka/kafka-cluster.yaml"
  kubectl -n messaging wait --for=condition=Ready kafka/foundation-kafka --timeout=1200s

  log "applying base Kafka Connect cluster"
  kubectl apply -f "${BASE_DIR}/resources/kafka/kafka-connect.yaml"
  kubectl -n messaging wait --for=condition=Ready kafkaconnect/foundation-connect --timeout=900s
}

apply_base() {
  require_k8s_tools
  preflight
  confirm_apply "This will install or update the Kubernetes production base on the current context" "$AUTO_APPROVE"

  log "applying namespaces and Pod Security labels"
  kubectl apply -f "${BASE_DIR}/manifests/namespace-baseline.yaml"

  check_optional_profile_inputs
  apply_gateway_api

  log "installing cert-manager first"
  (cd "$BASE_DIR" && helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" apply --selector profile=certificates)

  apply_cluster_issuers_if_configured
  apply_rabbitmq_operators
  apply_plugin_barman_cloud
  create_grafana_admin_secret

  log "applying helmfile environment ${ENVIRONMENT}"
  (cd "$BASE_DIR" && helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" apply)

  log "applying base Gateway"
  kubectl apply -f "${BASE_DIR}/manifests/gateway.yaml"

  apply_monitoring_resources

  wait_for_controllers
  apply_kafka_base
}

case "$ACTION" in
  check)
    preflight
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
