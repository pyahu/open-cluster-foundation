#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

SITE_ROOT="${OCF_ROOT}/dist"

require_command lychee
require_command rg
require_command yq
require_file "${OCF_ROOT}/.openai/hosting.json"
require_file "${SITE_ROOT}/index.html"
require_file "${SITE_ROOT}/404.html"
require_file "${SITE_ROOT}/docs/index.html"
require_file "${SITE_ROOT}/docs/cli/index.html"
require_file "${SITE_ROOT}/docs/architecture/index.html"
require_file "${SITE_ROOT}/assets/styles.css"
require_file "${SITE_ROOT}/assets/docs.css"
require_file "${SITE_ROOT}/assets/favicon.svg"
require_file "${SITE_ROOT}/robots.txt"
require_file "${SITE_ROOT}/sitemap.xml"

LATEST_RELEASE="$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1/p' "${OCF_ROOT}/CHANGELOG.md" | head -n 1)"
E2E_KUBERNETES_VERSION="$(yq -er '.e2e.kubernetesVersion' "${OCF_ROOT}/kubernetes/production-base/versions.yaml")"
[[ "$(yq -r '.static.directory' "${OCF_ROOT}/.openai/hosting.json")" == "dist" ]] || die "site hosting directory must be dist"
[[ -n "$(yq -r '.project_id // ""' "${OCF_ROOT}/.openai/hosting.json")" ]] || die "site hosting project_id is required"
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

lychee --offline --no-progress --root-dir "$SITE_ROOT" "${SITE_ROOT}/**/*.html"
log "site checks passed"
