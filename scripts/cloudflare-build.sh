#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_ROOT="${PROJECT_ROOT}/website/dist"

cd "${PROJECT_ROOT}/website"
npm ci
npm run check
npm run build

for required_file in \
  index.html \
  404.html \
  docs/index.html \
  docs/cli/index.html \
  docs/architecture/index.html \
  assets/mark.svg \
  _headers \
  robots.txt \
  pagefind/pagefind.js \
  sitemap-index.xml; do
  test -f "${SITE_ROOT}/${required_file}" || {
    printf 'missing Cloudflare static asset: website/dist/%s\n' "$required_file" >&2
    exit 1
  }
done

test -f "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'missing Cloudflare configuration: wrangler.toml\n' >&2
  exit 1
}

grep -Fq 'name = "open-cluster-foundation"' "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'Cloudflare Worker name must be open-cluster-foundation\n' >&2
  exit 1
}

grep -Fq '[assets]' "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'Cloudflare static assets configuration is required\n' >&2
  exit 1
}

grep -Fq 'directory = "./website/dist"' "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'Cloudflare static assets directory must be ./website/dist\n' >&2
  exit 1
}

grep -Fq 'not_found_handling = "404-page"' "${PROJECT_ROOT}/wrangler.toml" || {
  printf 'Cloudflare static assets must use the custom 404 page\n' >&2
  exit 1
}

printf 'Cloudflare static assets are ready in website/dist\n'
