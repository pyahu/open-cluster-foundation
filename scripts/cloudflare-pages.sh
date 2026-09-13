#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SITE_ROOT="${OCF_ROOT}/dist"
SITE_CONFIG="${OCF_ROOT}/wrangler.toml"

usage() {
  cat <<'EOF'
Usage:
  scripts/cloudflare-pages.sh dev
  scripts/cloudflare-pages.sh deploy [--yes]

Commands:
  dev       Run the Cloudflare Pages development server on port 4173.
  deploy    Deploy main to an existing Git-integrated Pages project.

The deploy command requires a clean main branch and explicit confirmation.
Create the Pages project with Git integration before using it.
EOF
}

load_project_name() {
  require_command yq
  require_file "$SITE_CONFIG"
  yq -er '.name' "$SITE_CONFIG"
}

run_dev_server() {
  require_command wrangler
  require_file "${SITE_ROOT}/index.html"
  cd "$OCF_ROOT"
  exec wrangler pages dev --port "${OCF_SITE_PORT:-4173}"
}

deploy_site() {
  local auto_approve="false"
  local current_branch
  local project_name
  local projects

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
  require_command jq
  require_command wrangler
  project_name="$(load_project_name)"
  current_branch="$(git -C "$OCF_ROOT" branch --show-current)"
  [[ "$current_branch" == "main" ]] || die "production site deploys must run from main"
  [[ -z "$(git -C "$OCF_ROOT" status --porcelain)" ]] || die "production site deploys require a clean working tree"
  [[ "$(git -C "$OCF_ROOT" rev-parse HEAD)" == "$(git -C "$OCF_ROOT" rev-parse origin/main)" ]] || die "main must match origin/main before deployment"

  "${SCRIPT_DIR}/ci-site.sh"
  projects="$(cd "$OCF_ROOT" && wrangler pages project list --json)"
  jq -e --arg name "$project_name" 'map(select(.name == $name)) | length == 1' <<<"$projects" >/dev/null || die "Cloudflare Pages project ${project_name} was not found. Create it with Git integration first"
  confirm_apply "This will deploy ${project_name} from main to Cloudflare Pages" "$auto_approve"

  cd "$OCF_ROOT"
  exec wrangler pages deploy "$SITE_ROOT" --project-name "$project_name" --branch main
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
