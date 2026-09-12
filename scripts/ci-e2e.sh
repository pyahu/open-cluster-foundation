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
CALICO_MANIFEST="$(mktemp)"

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
require_command yq

install_helm_diff() {
  local version
  local installed_version
  local repository
  local commit
  local platform
  local architecture
  local checksum_key
  local checksum
  local archive
  local install_status

  version="$(component_value helmDiff version)"
  installed_version="$(helm plugin list 2>/dev/null | awk '$1 == "diff" { print $2 }')"
  if [[ "$installed_version" == "${version#v}" ]]; then
    return
  fi
  [[ -z "$installed_version" ]] || die "helm diff ${version#v} is required; found ${installed_version}"

  repository="$(component_value helmDiff repository)"
  commit="$(component_value helmDiff commit)"
  case "$(uname -s)" in
    Darwin) platform="macos" ;;
    Linux) platform="linux" ;;
    *) die "unsupported helm diff platform: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) architecture="amd64" ;;
    arm64 | aarch64) architecture="arm64" ;;
    *) die "unsupported helm diff architecture: $(uname -m)" ;;
  esac
  checksum_key="${platform}$(tr '[:lower:]' '[:upper:]' <<<"${architecture:0:1}")${architecture:1}Sha256"
  checksum="$(component_value helmDiff "$checksum_key")"
  archive="$(mktemp)"
  download_verified \
    "${repository}/releases/download/${version}/helm-diff-${platform}-${architecture}.tgz" \
    "$checksum" \
    "$archive"
  install_status=0
  HELM_DIFF_BIN_TGZ="$archive" helm plugin install "$repository" --version "$commit" --verify=false || install_status=$?
  rm -f "$archive"
  [[ "$install_status" -eq 0 ]] || die "helm diff installation failed"
}

install_helm_diff

dump_diagnostics() {
  warn "e2e failed; dumping cluster state"
  kubectl get pods -A -o wide || true
  kubectl get events -A --sort-by=.lastTimestamp | tail -40 || true
  kubectl get gateway,httproute -A || true
  kubectl -n messaging get kafka,kafkaconnect,kafkanodepools || true
  kubectl -n data get clusters.postgresql.cnpg.io,backups.postgresql.cnpg.io,objectstores.barmancloud.cnpg.io || true
  kubectl -n data get jobs || true

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
  rm -f "$CALICO_MANIFEST"
  exit "$code"
}
trap cleanup EXIT

log "creating kind cluster ${CLUSTER_NAME}"
kind create cluster --name "$CLUSTER_NAME" --config "${E2E_DIR}/kind-config.yaml"

CALICO_VERSION="$(component_value calico version)"
log "installing Calico ${CALICO_VERSION} for NetworkPolicy enforcement"
download_verified \
  "$(component_value calico manifest)" \
  "$(component_value calico manifestSha256)" \
  "$CALICO_MANIFEST"
yq -i '(
  select(.kind == "DaemonSet" and .metadata.name == "calico-node") |
  .spec.template.spec.containers[] |
  select(.name == "calico-node") |
  .env[] |
  select(.name == "CALICO_IPV4POOL_IPIP") |
  .value
) = "Never" | (
  select(.kind == "DaemonSet" and .metadata.name == "calico-node") |
  .spec.template.spec.containers[] |
  select(.name == "calico-node") |
  .env[] |
  select(.name == "CALICO_IPV4POOL_VXLAN") |
  .value
) = "Always" | (
  select(.kind == "DaemonSet" and .metadata.name == "calico-node") |
  .spec.template.spec.containers[] |
  select(.name == "calico-node") |
  .env[] |
  select(.name == "CALICO_IPV4POOL_CIDR") |
  .value
) = "10.244.0.0/16"' "$CALICO_MANIFEST"
kubectl create -f "$CALICO_MANIFEST"
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl -n kube-system rollout status deployment/calico-kube-controllers --timeout=300s
kubectl -n kube-system rollout status deployment/coredns --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl run e2e-network-smoke \
  --image=curlimages/curl:8.17.0@sha256:935d9100e9ba842cdb060de42472c7ca90cfe9a7c96e4dacb55e79e560b3ff40 \
  --restart=Never \
  --command -- \
  sh -ec "attempt=0; until curl --insecure --fail --show-error --silent --connect-timeout 2 --max-time 5 --output /dev/null https://kubernetes.default.svc/version; do attempt=\$((attempt + 1)); [ \"\$attempt\" -ge 30 ] && exit 1; sleep 2; done"
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/e2e-network-smoke --timeout=120s
kubectl delete pod e2e-network-smoke --wait=true

log "installing the Kubernetes production base (ci environment)"
export OCF_K8S_ENVIRONMENT=ci
export OCF_AUTO_APPROVE=true
export OCF_HELMFILE_SUPPRESS_DIFF=true
export OCF_KAFKA_CLUSTER_FILE="${E2E_DIR}/kafka-smoke-cluster.yaml"
export OCF_KAFKA_CONNECT_FILE="${E2E_DIR}/kafka-smoke-connect.yaml"
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
route_reason() {
  kubectl -n e2e-untrusted get httproute e2e-untrusted -o json |
    jq -r '.status.parents[]?.conditions[]? | select(.type == "Accepted") | .reason' |
    head -1
}

wait_for_route_reason() {
  local expected="$1"
  local actual=""
  for _ in $(seq 1 60); do
    actual="$(route_reason)"
    [[ "$actual" == "$expected" ]] && return
    sleep 2
  done
  die "HTTPRoute reason is ${actual:-missing}; expected ${expected}"
}

wait_for_route_reason NotAllowedByListeners
kubectl label namespace e2e-untrusted open-cluster-foundation.io/gateway-access=public
kubectl -n e2e-untrusted delete httproute e2e-untrusted --wait=true
kubectl apply -f "${E2E_DIR}/untrusted-route.yaml"
wait_for_route_reason Accepted
kubectl label namespace e2e-untrusted open-cluster-foundation.io/gateway-access-
kubectl -n e2e-untrusted delete httproute e2e-untrusted --wait=true
kubectl apply -f "${E2E_DIR}/untrusted-route.yaml"
wait_for_route_reason NotAllowedByListeners

log "asserting base namespace NetworkPolicies are installed"
NETWORK_POLICY_COUNT="$(kubectl get networkpolicy --all-namespaces -l app.kubernetes.io/part-of=open-cluster-foundation --no-headers | wc -l | tr -d ' ')"
[[ "$NETWORK_POLICY_COUNT" -ge 20 ]] || die "expected at least 20 base NetworkPolicies, found ${NETWORK_POLICY_COUNT}"

log "asserting cert-manager issues a certificate"
kubectl apply -f "${E2E_DIR}/selfsigned-certificate.yaml"
kubectl -n default wait --for=condition=Ready certificate/e2e-selfsigned --timeout=180s

log "asserting Kafka preserves an exact produced message"
kubectl -n messaging wait --for=condition=Ready kafkatopic/e2e-events --timeout=300s
assert_kafka_message() {
  local pool="$1"
  local pod
  local message
  local consumed
  pod="$(kubectl -n messaging get pods \
    -l "strimzi.io/cluster=foundation-kafka,strimzi.io/pool-name=${pool}" \
    -o json |
    jq -r '.items[] | select(any(.spec.containers[]; .name == "kafka")) | .metadata.name' |
    head -1)"
  [[ -n "$pod" ]] || die "Kafka ${pool} pod not found"
  message="ocf-e2e-kafka-${pool}-$(date +%s)"
  printf '%s\n' "$message" |
    kubectl -n messaging exec -i "$pod" -c kafka -- \
      /opt/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server localhost:9092 \
      --topic e2e-events
  consumed="$(kubectl -n messaging exec "$pod" -c kafka -- \
    /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic e2e-events \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 60000)"
  [[ "$consumed" == "$message" ]] || die "Kafka consumed an unexpected message: ${consumed}"
}
assert_kafka_message dual

log "asserting Valkey answers PING"
VALKEY_POD="$(kubectl -n cache get pod -l app.kubernetes.io/name=valkey -o name | head -1)"
[[ -n "$VALKEY_POD" ]] || die "no valkey pod found"
kubectl -n cache exec "$VALKEY_POD" -c valkey -- valkey-cli ping 2>&1 | grep -q NOAUTH
VALKEY_PASSWORD="$(kubectl -n cache get secret valkey-acl -o go-template='{{ index .data "default" | base64decode }}')"
kubectl -n cache exec "$VALKEY_POD" -c valkey -- env REDISCLI_AUTH="$VALKEY_PASSWORD" valkey-cli ping | grep -q PONG
unset VALKEY_PASSWORD

log "asserting NetworkPolicy identity gates and observability data paths"
kubectl apply -f "${E2E_DIR}/clients.yaml"
kubectl -n e2e-untrusted wait --for=condition=Ready pod/e2e-ingest-client --timeout=180s
kubectl -n monitoring wait --for=condition=Ready pod/e2e-query-client --timeout=180s

ingest_curl() {
  kubectl -n e2e-untrusted exec -i e2e-ingest-client -- curl "$@"
}

query_curl() {
  kubectl -n monitoring exec e2e-query-client -- curl "$@"
}

if ingest_curl --fail --silent --show-error --connect-timeout 2 --max-time 4 \
  http://loki.monitoring.svc.cluster.local:3100/ready >/dev/null 2>&1; then
  die "untrusted workload reached Loki without observability identity"
fi
kubectl label namespace e2e-untrusted open-cluster-foundation.io/observability-access=true
if ingest_curl --fail --silent --show-error --connect-timeout 2 --max-time 4 \
  http://loki.monitoring.svc.cluster.local:3100/ready >/dev/null 2>&1; then
  die "namespace identity alone bypassed the observability workload identity gate"
fi
kubectl -n e2e-untrusted label pod e2e-ingest-client open-cluster-foundation.io/telemetry-client=trusted

for _ in $(seq 1 30); do
  ingest_curl --fail --silent --show-error --connect-timeout 2 --max-time 4 \
    http://loki.monitoring.svc.cluster.local:3100/ready >/dev/null 2>&1 && break
  sleep 2
done
ingest_curl --fail --silent --show-error --connect-timeout 2 --max-time 4 \
  http://loki.monitoring.svc.cluster.local:3100/ready >/dev/null ||
  die "trusted telemetry workload could not reach Loki"

LOKI_MARKER="ocf-e2e-loki-$(date +%s)"
LOKI_PAYLOAD="$(jq -cn \
  --arg timestamp "$(date +%s)000000000" \
  --arg marker "$LOKI_MARKER" \
  '{streams: [{stream: {job: "ocf-e2e"}, values: [[$timestamp, $marker]]}]}')"
ingest_curl --fail --silent --show-error \
  --header 'Content-Type: application/json' \
  --data "$LOKI_PAYLOAD" \
  http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push >/dev/null
LOKI_RESULT=""
for _ in $(seq 1 30); do
  LOKI_RESULT="$(query_curl --fail --silent --show-error --get \
    --data-urlencode 'query={job="ocf-e2e"}' \
    --data-urlencode 'since=5m' \
    http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query_range)"
  grep -q "$LOKI_MARKER" <<<"$LOKI_RESULT" && break
  sleep 2
done
grep -q "$LOKI_MARKER" <<<"$LOKI_RESULT" || die "Loki did not return the ingested marker"

TRACE_ID="$(openssl rand -hex 16)"
SPAN_ID="$(openssl rand -hex 8)"
TRACE_START="$(date +%s)000000000"
TRACE_END="$((TRACE_START + 1000000))"
TEMPO_PAYLOAD="$(jq -cn \
  --arg trace_id "$TRACE_ID" \
  --arg span_id "$SPAN_ID" \
  --arg start "$TRACE_START" \
  --arg end "$TRACE_END" \
  '{resourceSpans: [{resource: {attributes: [{key: "service.name", value: {stringValue: "ocf-e2e"}}]}, scopeSpans: [{scope: {name: "ocf-e2e"}, spans: [{traceId: $trace_id, spanId: $span_id, name: "e2e-span", kind: 1, startTimeUnixNano: $start, endTimeUnixNano: $end, status: {code: 1}}]}]}]}')"
ingest_curl --fail --silent --show-error \
  --header 'Content-Type: application/json' \
  --data "$TEMPO_PAYLOAD" \
  http://tempo.monitoring.svc.cluster.local:4318/v1/traces >/dev/null
TEMPO_RESULT=""
for _ in $(seq 1 30); do
  TEMPO_RESULT="$(query_curl --fail --silent --show-error \
    "http://tempo.monitoring.svc.cluster.local:3200/api/traces/${TRACE_ID}" 2>/dev/null || true)"
  grep -q 'e2e-span' <<<"$TEMPO_RESULT" && break
  sleep 2
done
grep -q 'e2e-span' <<<"$TEMPO_RESULT" || die "Tempo did not return the ingested trace"

if printf 'PING\r\nQUIT\r\n' | ingest_curl --silent --show-error --connect-timeout 2 --max-time 4 \
  telnet://valkey.cache.svc.cluster.local:6379 >/dev/null 2>&1; then
  die "untrusted workload reached Valkey without platform identity"
fi
kubectl label namespace e2e-untrusted open-cluster-foundation.io/platform-access=true
CACHE_RESPONSE=""
for _ in $(seq 1 30); do
  CACHE_RESPONSE="$(printf 'PING\r\nQUIT\r\n' |
    ingest_curl --silent --show-error --connect-timeout 2 --max-time 4 \
      telnet://valkey.cache.svc.cluster.local:6379 2>/dev/null || true)"
  grep -q NOAUTH <<<"$CACHE_RESPONSE" && break
  sleep 2
done
grep -q NOAUTH <<<"$CACHE_RESPONSE" || die "platform workload did not reach authenticated Valkey"

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

log "releasing validated full-stack workloads"
kubectl delete -f "${E2E_DIR}/kafka-smoke-connect.yaml" --ignore-not-found --wait=true --timeout=300s
kubectl -n messaging delete kafkatopic e2e-events --ignore-not-found --wait=true --timeout=300s
kubectl -n messaging delete kafka foundation-kafka --ignore-not-found --wait=true --timeout=300s
kubectl -n messaging delete kafkanodepool dual --ignore-not-found --wait=true --timeout=300s
for namespace in argocd cache cert-manager envoy-gateway-system monitoring rabbitmq-system reloader; do
  scale_namespaced_workloads_to_zero "$namespace"
  kubectl -n "$namespace" delete daemonset --all --ignore-not-found --wait=false
done
kubectl -n default delete deployment e2e-echo --wait=true
kubectl -n monitoring delete pod --all --wait=true --timeout=300s

log "asserting Kafka production topology on CI-sized storage"
kubectl apply -f "${E2E_DIR}/kafka-cluster.yaml"
kubectl -n messaging wait --for=condition=Ready kafka/foundation-kafka --timeout=600s
kubectl apply -f "${E2E_DIR}/kafka-connect.yaml"
kubectl -n messaging wait --for=condition=Ready kafkaconnect/foundation-connect --timeout=600s
kubectl -n messaging wait --for=condition=Ready kafkatopic/e2e-events --timeout=300s
for pool in controller broker; do
  EXPECTED_POOL_REPLICAS=3
  [[ "$pool" == "controller" ]] && EXPECTED_POOL_REPLICAS=1
  POOL_REPLICAS="$(kubectl -n messaging get kafkanodepool "$pool" -o jsonpath='{.spec.replicas}')"
  [[ "$POOL_REPLICAS" == "$EXPECTED_POOL_REPLICAS" ]] ||
    die "Kafka ${pool} pool has ${POOL_REPLICAS} replicas; expected ${EXPECTED_POOL_REPLICAS}"
  POOL_ROLE="$(kubectl -n messaging get kafkanodepool "$pool" -o jsonpath='{.spec.roles[0]}')"
  [[ "$POOL_ROLE" == "$pool" ]] || die "Kafka ${pool} pool has unexpected role ${POOL_ROLE}"
  POOL_NODES="$(kubectl -n messaging get pods \
    -l "strimzi.io/cluster=foundation-kafka,strimzi.io/pool-name=${pool}" \
    -o json | jq '[.items[].spec.nodeName] | unique | length')"
  [[ "$POOL_NODES" == "$EXPECTED_POOL_REPLICAS" ]] ||
    die "Kafka ${pool} replicas span ${POOL_NODES} nodes; expected ${EXPECTED_POOL_REPLICAS}"
done
assert_kafka_message broker

kubectl delete -f "${E2E_DIR}/kafka-connect.yaml" --ignore-not-found --wait=true --timeout=300s
kubectl -n messaging delete kafkatopic e2e-events --ignore-not-found --wait=true --timeout=300s
kubectl -n messaging delete kafka foundation-kafka --ignore-not-found --wait=true --timeout=300s
kubectl -n messaging delete kafkanodepool controller broker --ignore-not-found --wait=true --timeout=300s
scale_namespaced_workloads_to_zero messaging
scale_namespaced_workloads_to_zero strimzi-system

log "preparing S3-compatible storage for CloudNativePG recovery"
kubectl apply -f "${E2E_DIR}/cnpg-object-store.yaml"
kubectl -n data rollout status deployment/e2e-minio --timeout=300s
kubectl -n data wait --for=condition=Complete job/e2e-minio-bucket --timeout=300s

log "asserting CloudNativePG backup and physical restore preserve data"
kubectl apply -f "${E2E_DIR}/cnpg-cluster.yaml"
kubectl -n data wait --for=condition=Ready cluster/e2e-postgres --timeout=600s
POSTGRES_MARKER="ocf-e2e-postgres-$(date +%s)"
kubectl -n data exec e2e-postgres-1 -c postgres -- \
  psql --dbname postgres --set ON_ERROR_STOP=1 \
  --command "CREATE TABLE ocf_restore_probe (id integer PRIMARY KEY, payload text NOT NULL); INSERT INTO ocf_restore_probe VALUES (1, '${POSTGRES_MARKER}');"
kubectl apply -f "${E2E_DIR}/cnpg-backup.yaml"
kubectl -n data wait --for=jsonpath='{.status.phase}'=completed backup/e2e-postgres-backup --timeout=900s
kubectl apply -f "${E2E_DIR}/cnpg-restore.yaml"
kubectl -n data wait --for=condition=Ready cluster/e2e-postgres-restore --timeout=900s
RESTORED_MARKER="$(kubectl -n data exec e2e-postgres-restore-1 -c postgres -- \
  psql --dbname postgres --tuples-only --no-align --set ON_ERROR_STOP=1 \
  --command 'SELECT payload FROM ocf_restore_probe WHERE id = 1')"
[[ "$RESTORED_MARKER" == "$POSTGRES_MARKER" ]] || die "CloudNativePG restore returned unexpected data: ${RESTORED_MARKER}"

log "e2e passed: edge authorization, NetworkPolicy isolation, TLS, Postgres, Kafka, cache, logs and traces are functional"
