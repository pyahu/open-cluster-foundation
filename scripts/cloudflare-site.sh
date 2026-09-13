#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SITE_ROOT="${OCF_ROOT}/dist"
SITE_CONFIG="${OCF_ROOT}/wrangler.toml"

usage() {
  cat <<'EOF'
Usage:
  scripts/cloudflare-site.sh dev
  scripts/cloudflare-site.sh deploy [--yes]

Commands:
  dev       Run the Cloudflare development server on port 4173.
  deploy    Deploy main with Cloudflare Workers Static Assets.

The deploy command requires a clean main branch and explicit confirmation.
EOF
}

load_worker_name() {
  require_command yq
  require_file "$SITE_CONFIG"
  yq -er '.name' "$SITE_CONFIG"
}

run_dev_server() {
  require_command wrangler
  require_file "${SITE_ROOT}/index.html"
  cd "$OCF_ROOT"
  exec wrangler dev --port "${OCF_SITE_PORT:-4173}"
}

deploy_site() {
  local auto_approve="false"
  local current_branch
  local worker_name

  shift
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --yes)
        auto_approve="true"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  require_command git
  require_command wrangler
  worker_name="$(load_worker_name)"
  current_branch="$(git -C "$OCF_ROOT" branch --show-current)"
  [[ "$current_branch" == "main" ]] || die "production site deploys must run from main"
  [[ -z "$(git -C "$OCF_ROOT" status --porcelain)" ]] || die "production site deploys require a clean working tree"
  [[ "$(git -C "$OCF_ROOT" rev-parse HEAD)" == "$(git -C "$OCF_ROOT" rev-parse origin/main)" ]] || die "main must match origin/main before deployment"

  "${SCRIPT_DIR}/ci-site.sh"
  confirm_apply "This will deploy ${worker_name} from main to Cloudflare" "$auto_approve"

  cd "$OCF_ROOT"
  exec wrangler deploy
}

case "${1:-}" in
  dev)
    run_dev_server
    ;;
  deploy)
    deploy_site "$@"
    ;;
  -h | --help | help | "")
    usage
    ;;
  *)
    die "unknown command: $1"
    ;;
esac
