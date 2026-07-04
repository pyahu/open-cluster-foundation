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
CPK_PID=""

# The whole run lives in a private kubeconfig so the operator's real contexts
# are never touched or repointed.
KUBECONFIG="$(mktemp)"
export KUBECONFIG

require_command docker
require_command kind
require_command cloud-provider-kind
require_command kubectl
require_command helm
require_command helmfile
require_command curl

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
  if [[ -n "$CPK_PID" ]]; then
    kill "$CPK_PID" 2>/dev/null || true
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

# Started only after the base install: cloud-provider-kind applies its own
# copy of the Gateway API CRDs at startup and would fight the foundation's
# server-side apply over field ownership.
log "starting cloud-provider-kind (LoadBalancer support)"
cloud-provider-kind >/tmp/cloud-provider-kind.log 2>&1 &
CPK_PID=$!

log "asserting the GatewayClass is accepted"
kubectl wait --for=condition=Accepted gatewayclass/envoy --timeout=120s

log "waiting for the Gateway to receive a LoadBalancer address"
GATEWAY_ADDRESS=""
for _ in $(seq 1 60); do
  GATEWAY_ADDRESS="$(kubectl -n platform-system get gateway public-gateway \
    -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
  [[ -n "$GATEWAY_ADDRESS" ]] && break
  sleep 5
done
[[ -n "$GATEWAY_ADDRESS" ]] || die "gateway never received an address (is cloud-provider-kind running?)"
log "gateway address: ${GATEWAY_ADDRESS}"

log "asserting HTTP traffic flows through the edge"
kubectl apply -f "${E2E_DIR}/echo.yaml"
kubectl -n default rollout status deploy/e2e-echo --timeout=180s

HTTP_CODE=""
for _ in $(seq 1 30); do
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Host: e2e.example.com" "http://${GATEWAY_ADDRESS}/hostname" || true)"
  [[ "$HTTP_CODE" == "200" ]] && break
  sleep 5
done
[[ "$HTTP_CODE" == "200" ]] || die "expected HTTP 200 through the gateway, got '${HTTP_CODE}'"

log "asserting cert-manager issues a certificate"
kubectl apply -f "${E2E_DIR}/selfsigned-certificate.yaml"
kubectl -n default wait --for=condition=Ready certificate/e2e-selfsigned --timeout=180s

log "asserting CloudNativePG reconciles a cluster to Ready"
kubectl apply -f "${E2E_DIR}/cnpg-cluster.yaml"
kubectl -n data wait --for=condition=Ready cluster/e2e-postgres --timeout=600s

log "asserting Valkey answers PING"
VALKEY_POD="$(kubectl -n cache get pod -l app.kubernetes.io/name=valkey -o name | head -1)"
[[ -n "$VALKEY_POD" ]] || die "no valkey pod found"
kubectl -n cache exec "$VALKEY_POD" -c valkey -- valkey-cli ping | grep -q PONG

log "asserting monitoring resources exist"
RULES="$(kubectl -n monitoring get prometheusrules -o name | wc -l)"
[[ "$RULES" -ge 4 ]] || die "expected at least 4 PrometheusRules in monitoring, found ${RULES}"
MONITORS="$(kubectl -n monitoring get podmonitors -o name | wc -l)"
[[ "$MONITORS" -ge 3 ]] || die "expected at least 3 PodMonitors in monitoring, found ${MONITORS}"

log "e2e passed: edge, TLS issuance, Postgres, Kafka, cache and monitoring are functional"
