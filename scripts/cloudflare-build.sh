#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_ROOT="${PROJECT_ROOT}/dist"

for required_file in \
  index.html \
  404.html \
  docs/index.html \
  docs/cli/index.html \
  docs/architecture/index.html \
  assets/styles.css \
  assets/docs.css \
  assets/favicon.svg \
  _headers \
  robots.txt; do
  test -f "${SITE_ROOT}/${required_file}" || {
    printf 'missing Cloudflare Pages asset: dist/%s\n' "$required_file" >&2
    exit 1
  }
done

test -f "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'missing Cloudflare Pages configuration: wrangler.toml\n' >&2
  exit 1
}

grep -Fq 'name = "open-cluster-foundation"' "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'Cloudflare Pages project name must be open-cluster-foundation\n' >&2
  exit 1
}

grep -Fq 'pages_build_output_dir = "./dist"' "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'Cloudflare Pages build output must be ./dist\n' >&2
  exit 1
}

printf 'Cloudflare Pages assets are ready in dist\n'
