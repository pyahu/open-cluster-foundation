#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SITE_ROOT="${OCF_ROOT}/dist"

"${SCRIPT_DIR}/cloudflare-build.sh"

require_command lychee
require_command rg
require_command yq
require_file "${OCF_ROOT}/wrangler.toml"
require_file "${SITE_ROOT}/index.html"
require_file "${SITE_ROOT}/404.html"
require_file "${SITE_ROOT}/docs/index.html"
require_file "${SITE_ROOT}/docs/cli/index.html"
require_file "${SITE_ROOT}/docs/architecture/index.html"
require_file "${SITE_ROOT}/assets/styles.css"
require_file "${SITE_ROOT}/assets/docs.css"
require_file "${SITE_ROOT}/assets/favicon.svg"
require_file "${SITE_ROOT}/_headers"
require_file "${SITE_ROOT}/robots.txt"

LATEST_RELEASE="$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1/p' "${OCF_ROOT}/CHANGELOG.md" | head -n 1)"
E2E_KUBERNETES_VERSION="$(yq -er '.e2e.kubernetesVersion' "${OCF_ROOT}/kubernetes/production-base/versions.yaml")"
PROJECT_NAME="$(yq -er '.name' "${OCF_ROOT}/wrangler.toml")"
BUILD_OUTPUT="$(yq -er '.assets.directory' "${OCF_ROOT}/wrangler.toml")"
COMPATIBILITY_DATE="$(yq -er '.compatibility_date' "${OCF_ROOT}/wrangler.toml")"
NOT_FOUND_HANDLING="$(yq -er '.assets.not_found_handling' "${OCF_ROOT}/wrangler.toml")"
[[ "$PROJECT_NAME" == "open-cluster-foundation" ]] || die "Cloudflare Worker name must be open-cluster-foundation"
[[ "$BUILD_OUTPUT" == "./dist" ]] || die "Cloudflare static assets directory must be ./dist"
[[ "$NOT_FOUND_HANDLING" == "404-page" ]] || die "Cloudflare static assets must use the custom 404 page"
[[ "$COMPATIBILITY_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "Cloudflare compatibility date must use yyyy-mm-dd"
[[ ! -e "${OCF_ROOT}/.openai/hosting.json" ]] || die "OpenAI Sites configuration must not coexist with Cloudflare hosting"
rg -Fq "v${LATEST_RELEASE}" "${SITE_ROOT}/docs/index.html" || die "site getting started guide must use v${LATEST_RELEASE}"
rg -Fq "$E2E_KUBERNETES_VERSION" "${SITE_ROOT}/index.html" || die "site must show tested Kubernetes ${E2E_KUBERNETES_VERSION}"
rg -Fq "$E2E_KUBERNETES_VERSION" "${SITE_ROOT}/docs/index.html" || die "site docs must show tested Kubernetes ${E2E_KUBERNETES_VERSION}"

while IFS= read -r html_file; do
  rg -Fq '<meta name="viewport"' "$html_file" || die "${html_file#"${OCF_ROOT}"/} needs a viewport"
  rg -Fq '<title>' "$html_file" || die "${html_file#"${OCF_ROOT}"/} needs a title"
  rg -Fq '<main' "$html_file" || die "${html_file#"${OCF_ROOT}"/} needs a main landmark"
done < <(find "$SITE_ROOT" -type f -name '*.html' -print)

if rg -n '[\x{2013}\x{2014}]|,[[:space:]]+[Aa]nd\b' "$SITE_ROOT" --glob '*.{html,css,js}'; then
  die "site copy must use plain punctuation and omit the comma before and"
fi

if rg -n 'chatgpt\.site' "$SITE_ROOT" "$OCF_ROOT/README.md" "$OCF_ROOT/docs"; then
  die "site and documentation must not reference the retired hosting provider"
fi

rg -Fq "Content-Security-Policy:" "${SITE_ROOT}/_headers" || die "site security headers must include a content security policy"
rg -Fq "X-Content-Type-Options: nosniff" "${SITE_ROOT}/_headers" || die "site security headers must disable MIME sniffing"

lychee --offline --no-progress --root-dir "$SITE_ROOT" "${SITE_ROOT}/**/*.html"
log "site checks passed"
