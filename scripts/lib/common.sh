#!/usr/bin/env bash

set -Eeuo pipefail

OCF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log() {
  printf '[open-cluster-foundation] %s\n' "$*"
}

warn() {
  printf '[open-cluster-foundation] warning: %s\n' "$*" >&2
}

die() {
  printf '[open-cluster-foundation] error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || die "required command not found: ${command_name}"
}

require_file() {
  local file_path="$1"
  local help_text="${2:-}"

  if [[ -f "$file_path" ]]; then
    return
  fi

  if [[ -n "$help_text" ]]; then
    die "missing required file: ${file_path}. ${help_text}"
  fi

  die "missing required file: ${file_path}"
}

confirm_apply() {
  local message="$1"
  local auto_approve="$2"

  if [[ "$auto_approve" == "true" ]]; then
    return
  fi

  if [[ ! -t 0 ]]; then
    die "${message}. Re-run with --yes for non-interactive execution."
  fi

  printf '%s\n' "$message"
  printf 'Type "apply" to continue: '

  local answer
  read -r answer

  [[ "$answer" == "apply" ]] || die "confirmation failed"
}

component_value() {
  local component="$1"
  local key="$2"
  local versions_file="${OCF_ROOT}/kubernetes/production-base/versions.yaml"

  awk -v component="$component" -v key="$key" '
    $0 ~ "^  " component ":" {
      in_component = 1
      next
    }
    in_component && $0 ~ "^  [A-Za-z0-9]+:" {
      exit
    }
    in_component && $0 ~ "^    " key ":" {
      sub("^[[:space:]]*" key ":[[:space:]]*", "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$versions_file"
}
