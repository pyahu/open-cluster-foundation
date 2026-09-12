#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# End-to-end test: installs the full Kubernetes production base on a
# disposable kind cluster and asserts it actually works — the integration
# test the render/schema checks cannot provide.
#
# Environment:
#   OCF_E2E_CLUSTER   kind cluster name. Defaults to "ocf-e2e".
#   OCF_E2E_KEEP=true Keep the kind cluster after the run (local debugging).

CLUSTER_NAME="${OCF_E2E_CLUSTER:-ocf-e2e}"
KEEP="${OCF_E2E_KEEP:-false}"
E2E_DIR="${OCF_ROOT}/test/e2e"
GATEWAY_FORWARD_PID=""

# The whole run lives in a private kubeconfig so the operator's real contexts
# are never touched or repointed.
KUBECONFIG="$(mktemp)"
export KUBECONFIG

require_command docker
require_command kind
require_command kubectl
require_command helm
require_command helmfile
require_command curl
require_command jq

# helmfile apply needs the helm-diff plugin; install it when missing.
# helm 4 verifies plugin signatures by default, which git sources do not support.
helm plugin list 2>/dev/null | grep -q '^diff' ||
  helm plugin install https://github.com/databus23/helm-diff --version v3.15.10 --verify=false

dump_diagnostics() {
  warn "e2e failed; dumping cluster state"
  kubectl get pods -A -o wide || true
  kubectl get events -A --sort-by=.lastTimestamp | tail -40 || true
  kubectl get gateway,httproute -A || true
  kubectl -n messaging get kafka,kafkaconnect,kafkanodepools || true
  kubectl -n data get clusters.postgresql.cnpg.io || true

  # Logs of every pod that is not fully ready, so crash causes survive the
  # cluster teardown.
  kubectl get pods -A --no-headers 2>/dev/null |
    awk '{ split($3, ready, "/"); if (ready[1] != ready[2] || ($4 != "Running" && $4 != "Completed")) print $1, $2 }' |
    while read -r ns pod; do
      # The event tail of describe carries the failures that never reach a log:
      # image pulls, scheduling, missing secrets.
      warn "events for ${ns}/${pod}"
      kubectl -n "$ns" describe pod "$pod" 2>/dev/null | tail -20 || true
      warn "logs for ${ns}/${pod}"
      kubectl -n "$ns" logs "$pod" --all-containers --tail=30 --prefix 2>/dev/null || true
      kubectl -n "$ns" logs "$pod" --all-containers --tail=15 --prefix --previous 2>/dev/null || true
    done
}

cleanup() {
  local code=$?
  if [[ $code -ne 0 ]]; then
    dump_diagnostics
  fi
  if [[ -n "$GATEWAY_FORWARD_PID" ]]; then
    kill "$GATEWAY_FORWARD_PID" 2>/dev/null || true
    wait "$GATEWAY_FORWARD_PID" 2>/dev/null || true
  fi
  if [[ "$KEEP" != "true" ]]; then
    kind delete cluster --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
    rm -f "$KUBECONFIG"
  fi
  exit "$code"
}
trap cleanup EXIT

log "creating kind cluster ${CLUSTER_NAME}"
kind create cluster --name "$CLUSTER_NAME" --config "${E2E_DIR}/kind-config.yaml" --wait 180s

log "installing the Kubernetes production base (ci environment)"
export OCF_K8S_ENVIRONMENT=ci
export OCF_AUTO_APPROVE=true
export OCF_KAFKA_CLUSTER_FILE="${E2E_DIR}/kafka-cluster.yaml"
export OCF_KAFKA_CONNECT_FILE="${E2E_DIR}/kafka-connect.yaml"
"${SCRIPT_DIR}/k8s-production-base.sh" apply --yes

log "asserting fresh-install state was recorded"
STATE_CONFIGMAP="open-cluster-foundation-installation"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "schema-version" }}')" == "1" ]] || die "unexpected installation state schema"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "environment" }}')" == "ci" ]] || die "unexpected installation state environment"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "mode" }}')" == "fresh" ]] || die "unexpected installation state mode"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "origin" }}')" == "fresh" ]] || die "unexpected installation state origin"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "network-policies" }}')" == "enforced" ]] || die "unexpected installation NetworkPolicy state"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "observability-scope" }}')" == "trusted" ]] || die "unexpected installation observability scope"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "identity-access" }}')" == "sso" ]] || die "unexpected installation identity access mode"
[[ "$(kubectl -n platform-system get configmap "$STATE_CONFIGMAP" -o go-template='{{ index .data "cache-access" }}')" == "acl" ]] || die "unexpected installation cache access mode"
"${SCRIPT_DIR}/k8s-production-base.sh" check --mode upgrade
if "${SCRIPT_DIR}/k8s-production-base.sh" check --mode fresh >/dev/null 2>&1; then
  die "fresh mode accepted an existing managed installation"
fi

log "asserting the GatewayClass is accepted"
kubectl wait --for=condition=Accepted gatewayclass/envoy --timeout=120s

log "waiting for the Envoy data-plane service"
GATEWAY_SERVICE=""
for _ in $(seq 1 60); do
  GATEWAY_SERVICE="$(kubectl -n envoy-gateway-system get service \
    -l gateway.envoyproxy.io/owning-gateway-namespace=platform-system,gateway.envoyproxy.io/owning-gateway-name=public-gateway \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "$GATEWAY_SERVICE" ]] && break
  sleep 2
done
[[ -n "$GATEWAY_SERVICE" ]] || die "Envoy data-plane service was not created"
kubectl -n envoy-gateway-system port-forward "service/${GATEWAY_SERVICE}" 18080:80 >/tmp/ocf-e2e-gateway-forward.log 2>&1 &
GATEWAY_FORWARD_PID=$!

log "asserting HTTP traffic flows through the edge"
kubectl label namespace default open-cluster-foundation.io/gateway-access=public
kubectl apply -f "${E2E_DIR}/echo.yaml"
kubectl -n default rollout status deploy/e2e-echo --timeout=180s

HTTP_CODE=""
for _ in $(seq 1 30); do
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Host: e2e.example.com" "http://127.0.0.1:18080/hostname" || true)"
  [[ "$HTTP_CODE" == "200" ]] && break
  sleep 5
done
[[ "$HTTP_CODE" == "200" ]] || die "expected HTTP 200 through the gateway, got '${HTTP_CODE}'"

log "asserting an unlabeled namespace cannot attach a public route"
kubectl apply -f "${E2E_DIR}/untrusted-route.yaml"
UNTRUSTED_REASON=""
for _ in $(seq 1 30); do
  UNTRUSTED_REASON="$(kubectl -n e2e-untrusted get httproute e2e-untrusted -o json |
    jq -r '.status.parents[]?.conditions[]? | select(.type == "Accepted") | .reason' | head -1)"
  [[ "$UNTRUSTED_REASON" == "NotAllowedByListeners" ]] && break
  sleep 2
done
[[ "$UNTRUSTED_REASON" == "NotAllowedByListeners" ]] || die "untrusted HTTPRoute was not rejected: ${UNTRUSTED_REASON:-no status}"

log "asserting base namespace NetworkPolicies are installed"
NETWORK_POLICY_COUNT="$(kubectl get networkpolicy --all-namespaces -l app.kubernetes.io/part-of=open-cluster-foundation --no-headers | wc -l | tr -d ' ')"
[[ "$NETWORK_POLICY_COUNT" -ge 20 ]] || die "expected at least 20 base NetworkPolicies, found ${NETWORK_POLICY_COUNT}"

log "asserting cert-manager issues a certificate"
kubectl apply -f "${E2E_DIR}/selfsigned-certificate.yaml"
kubectl -n default wait --for=condition=Ready certificate/e2e-selfsigned --timeout=180s

log "asserting CloudNativePG reconciles a cluster to Ready"
kubectl apply -f "${E2E_DIR}/cnpg-cluster.yaml"
kubectl -n data wait --for=condition=Ready cluster/e2e-postgres --timeout=600s

log "asserting Valkey answers PING"
VALKEY_POD="$(kubectl -n cache get pod -l app.kubernetes.io/name=valkey -o name | head -1)"
[[ -n "$VALKEY_POD" ]] || die "no valkey pod found"
kubectl -n cache exec "$VALKEY_POD" -c valkey -- valkey-cli ping 2>&1 | grep -q NOAUTH
VALKEY_PASSWORD="$(kubectl -n cache get secret valkey-acl -o go-template='{{ index .data "default" | base64decode }}')"
kubectl -n cache exec "$VALKEY_POD" -c valkey -- env REDISCLI_AUTH="$VALKEY_PASSWORD" valkey-cli ping | grep -q PONG
unset VALKEY_PASSWORD

log "asserting monitoring resources exist"
RULES="$(kubectl -n monitoring get prometheusrules -o name | wc -l)"
[[ "$RULES" -ge 4 ]] || die "expected at least 4 PrometheusRules in monitoring, found ${RULES}"
MONITORS="$(kubectl -n monitoring get podmonitors -o name | wc -l)"
[[ "$MONITORS" -ge 3 ]] || die "expected at least 3 PodMonitors in monitoring, found ${MONITORS}"

PROMETHEUS_NAME="$(kubectl -n monitoring get prometheus -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$PROMETHEUS_NAME" ]] || die "Prometheus custom resource not found"
for selector in serviceMonitorNamespaceSelector podMonitorNamespaceSelector ruleNamespaceSelector probeNamespaceSelector scrapeConfigNamespaceSelector; do
  selector_value="$(kubectl -n monitoring get prometheus "$PROMETHEUS_NAME" -o "go-template={{ index (index .spec.${selector}.matchLabels \"open-cluster-foundation.io/observability-access\") }}")"
  [[ "$selector_value" == "true" ]] || die "Prometheus ${selector} is not restricted to trusted namespaces"
done

kubectl -n monitoring get role grafana >/dev/null
if kubectl get clusterrole grafana >/dev/null 2>&1; then
  die "Grafana retained cluster-wide dashboard discovery RBAC"
fi

[[ "$(kubectl -n argocd get configmap argocd-cm -o go-template='{{ index .data "admin.enabled" }}')" == "false" ]] || die "Argo CD local admin is enabled on a fresh installation"
[[ "$(kubectl -n argocd get configmap argocd-rbac-cm -o go-template='{{ index .data "policy.default" }}')" == "role:authenticated" ]] || die "Argo CD grants read access by default"
GRAFANA_CONFIG="$(kubectl -n monitoring get configmap grafana -o go-template='{{ index .data "grafana.ini" }}')"
grep -q '^role_attribute_strict = true$' <<<"$GRAFANA_CONFIG" || die "Grafana does not require explicit role mapping"
grep -q '^allow_assign_grafana_admin = false$' <<<"$GRAFANA_CONFIG" || die "Grafana allows OAuth server-admin assignment"
if grep -q GrafanaAdmin <<<"$GRAFANA_CONFIG"; then
  die "Grafana grants server administrator through OAuth"
fi

[[ "$(kubectl -n monitoring get configmap strimzi-kafka -o jsonpath='{.metadata.namespace}')" == "monitoring" ]] || die "Strimzi dashboards are not colocated with Grafana"
kubectl -n monitoring get configmap alloy -o go-template='{{ index .data "config.alloy" }}' | grep -q 'open-cluster-foundation.io/telemetry-client=trusted' || die "Alloy is not filtering untrusted pod logs"

log "e2e passed: edge, TLS issuance, Postgres, Kafka, cache and monitoring are functional"
