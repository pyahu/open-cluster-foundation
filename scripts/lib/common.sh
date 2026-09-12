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

sha256_file() {
  local file_path="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file_path" | awk '{ print $1 }'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file_path" | awk '{ print $1 }'
    return
  fi

  die "required SHA-256 tool not found: sha256sum or shasum"
}

download_verified() {
  local url="$1"
  local expected_sha256="$2"
  local destination="$3"
  local download_path
  local actual_sha256

  [[ "$url" == https://* ]] || die "download URL must use HTTPS: ${url}"
  [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || die "invalid SHA-256 for ${url}"
  require_command curl

  download_path="$(mktemp "${destination}.download.XXXXXX")"
  if ! curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
    --output "$download_path" "$url"; then
    rm -f "$download_path"
    die "download failed: ${url}"
  fi

  actual_sha256="$(sha256_file "$download_path")"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    rm -f "$download_path"
    die "SHA-256 mismatch for ${url}: expected ${expected_sha256}, got ${actual_sha256}"
  fi

  mv "$download_path" "$destination"
}

scale_namespaced_workloads_to_zero() {
  local namespace="$1"
  local resource
  local resources=()
  local scale_output

  while IFS= read -r resource; do
    [[ -n "$resource" ]] && resources+=("$resource")
  done < <(kubectl -n "$namespace" get deployment,statefulset -o name)

  [[ "${#resources[@]}" -eq 0 ]] && return

  for resource in "${resources[@]}"; do
    if ! scale_output="$(kubectl -n "$namespace" scale "$resource" --replicas=0 2>&1)"; then
      [[ "$scale_output" == *"(NotFound)"* ]] && continue
      printf '%s\n' "$scale_output" >&2
      return 1
    fi
  done
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

profile_enabled() {
  local profile="$1"
  local environment="$2"
  local environments_file="${OCF_ROOT}/kubernetes/production-base/environments/${environment}.yaml"

  [[ -f "$environments_file" ]] || die "unknown helmfile environment: ${environment}"

  local value
  value="$(awk -v profile="$profile" '
    $0 ~ "^  " profile ":" {
      sub("^[[:space:]]*" profile ":[[:space:]]*", "")
      print
      exit
    }
  ' "$environments_file")"

  [[ "$value" == "true" ]]
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
