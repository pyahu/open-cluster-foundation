#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ACTION="${1:-}"
AUTO_APPROVE="${OCF_AUTO_APPROVE:-false}"

usage() {
  cat <<'EOF'
Usage:
  scripts/k8s-node-pools.sh taint-database [--yes]

Applies standard labels and taints to database nodes in the current Kubernetes
context. Nodes provisioned by the foundation register their taints via kubelet
at startup; this task retrofits nodes created before taints were configured and
adds the node-role.kubernetes.io/postgres label, which kubelet cannot
self-apply.
EOF
}

if [[ -z "$ACTION" || "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi

shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
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

taint_database() {
  require_command kubectl

  local context
  context="$(kubectl config current-context)"

  log "current Kubernetes context: ${context}"
  kubectl get nodes -l node-pool=database

  confirm_apply "This will label and taint nodes with node-pool=database in context ${context}" "$AUTO_APPROVE"

  kubectl label nodes \
    -l node-pool=database \
    node-role.kubernetes.io/postgres= \
    open-cluster-foundation.io/workload=database \
    --overwrite

  kubectl taint nodes \
    -l node-pool=database \
    workload.open-cluster-foundation.io/database=true:NoSchedule \
    --overwrite
}

case "$ACTION" in
  taint-database)
    taint_database
    ;;
  *)
    usage
    die "unknown action: ${ACTION}"
    ;;
esac
