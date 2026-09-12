#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-}"
CONTEXT=""
GATEWAY_NAMESPACE="platform-system"
GATEWAY_NAME="public-gateway"

usage() {
  cat <<'EOF'
Usage:
  scripts/k8s-gateway-access.sh check --context <context> [--namespace <namespace>] [--gateway <name>]

Checks whether every namespace with an HTTPRoute attached to the selected
Gateway has open-cluster-foundation.io/gateway-access=public. The command is
read-only and requires an explicit Kubernetes context.
EOF
}

if [[ -z "$ACTION" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context)
      CONTEXT="${2:-}"
      [[ -n "$CONTEXT" ]] || die "--context requires a value"
      shift
      ;;
    --namespace)
      GATEWAY_NAMESPACE="${2:-}"
      [[ -n "$GATEWAY_NAMESPACE" ]] || die "--namespace requires a value"
      shift
      ;;
    --gateway)
      GATEWAY_NAME="${2:-}"
      [[ -n "$GATEWAY_NAME" ]] || die "--gateway requires a value"
      shift
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

[[ "$ACTION" == "check" ]] || die "unknown action: ${ACTION}"
[[ -n "$CONTEXT" ]] || die "--context is required"

require_command jq
require_command kubectl

gateway_json="$(kubectl --context "$CONTEXT" -n "$GATEWAY_NAMESPACE" get gateway "$GATEWAY_NAME" -o json)"
route_json="$(kubectl --context "$CONTEXT" get httproutes.gateway.networking.k8s.io --all-namespaces -o json)"

log "Gateway ${GATEWAY_NAMESPACE}/${GATEWAY_NAME} listener access"
jq -r '.spec.listeners[] | "  \(.name): \(.allowedRoutes.namespaces.from // "Same")"' <<<"$gateway_json"

route_namespaces="$(jq -r --arg gateway_namespace "$GATEWAY_NAMESPACE" --arg gateway_name "$GATEWAY_NAME" '
  [
    .items[] as $route |
    $route.spec.parentRefs[]? |
    select((.group // "gateway.networking.k8s.io") == "gateway.networking.k8s.io") |
    select((.kind // "Gateway") == "Gateway") |
    select(.name == $gateway_name) |
    select((.namespace // $route.metadata.namespace) == $gateway_namespace) |
    $route.metadata.namespace
  ] | unique[]
' <<<"$route_json")"

missing=0
while IFS= read -r namespace; do
  [[ -n "$namespace" ]] || continue
  access="$(kubectl --context "$CONTEXT" get namespace "$namespace" -o go-template='{{ index .metadata.labels "open-cluster-foundation.io/gateway-access" }}')"
  if [[ "$access" == "public" ]]; then
    log "namespace ${namespace}: ready"
  else
    warn "namespace ${namespace}: missing open-cluster-foundation.io/gateway-access=public"
    missing=$((missing + 1))
  fi
done <<<"$route_namespaces"

[[ "$missing" -eq 0 ]] || die "${missing} route namespace(s) must be labeled before changing allowedRoutes to Selector"
log "all attached HTTPRoute namespaces are ready for selector-based attachment"
