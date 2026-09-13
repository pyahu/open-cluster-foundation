#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

require_command git
require_command rg
require_command sed

violations_file="$(mktemp)"
trap 'rm -f "$violations_file"' EXIT
scan_root="${OCF_COMMENT_SCAN_ROOT:-$OCF_ROOT}"

append_hash_violations() {
  local source_path="$1"
  local source_file="$2"
  local matches

  matches="$(rg -n '(^|[[:space:]])#' "$source_path" \
    | rg -v '^[0-9]+:[[:space:]]*#!/usr/bin/env bash[[:space:]]*$' \
    | rg -v '^[0-9]+:[[:space:]]*# renovate: datasource=[^[:space:]]+ depName=[^[:space:]]+( registryUrl=https://[^[:space:]]+)?[[:space:]]*$' \
    | rg -v '^[0-9]+:[[:space:]]*# shellcheck source=[^[:space:]]+[[:space:]]*$' \
    | rg -v '^[0-9]+:# This file is maintained automatically by "terraform init"\.$' \
    | rg -v '^[0-9]+:# Manual edits may be lost in future updates\.$' || true)"

  [[ -z "$matches" ]] || printf '%s\n' "$matches" | sed "s|^|${source_file}:|" >>"$violations_file"
}

append_slash_violations() {
  local source_path="$1"
  local source_file="$2"
  local matches
  local slash_pattern='^[[:space:]]*//'

  case "$source_file" in
    *.gotmpl | *.hcl | *.tf | *.tpl)
      slash_pattern='(^|[[:space:]])//'
      ;;
  esac

  matches="$(rg -n "${slash_pattern}|^[[:space:]]*/\\*|^[[:space:]]*\\*/|\\{\\{[-]?[[:space:]]*/\\*" "$source_path" || true)"
  [[ -z "$matches" ]] || printf '%s\n' "$matches" | sed "s|^|${source_file}:|" >>"$violations_file"
}

while IFS= read -r source_file; do
  case "$source_file" in
    .gitignore | Dockerfile* | Makefile | *.conf | *.env | *.env.example | *.gotmpl | *.hcl | *.ini | *.sh | *.tf | *.tfvars | *.tfvars.example | *.toml | *.tpl | *.yaml | *.yaml.example | *.yml)
      source_path="${scan_root}/${source_file}"
      append_hash_violations "$source_path" "$source_file"
      append_slash_violations "$source_path" "$source_file"
      ;;
  esac
done < <(git -C "$scan_root" ls-files)

if [[ -s "$violations_file" ]]; then
  cat "$violations_file" >&2
  die "source comments must move to documentation"
fi

log "source comment policy passed"
