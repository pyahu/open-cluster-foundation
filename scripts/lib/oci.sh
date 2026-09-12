#!/usr/bin/env bash

set -Eeuo pipefail

parse_legacy_kubeconfig_output() {
  local command_text="$1"
  local argument
  local flag
  local value
  local arguments=()

  read -r -a arguments <<<"$command_text"
  [[ "${#arguments[@]}" -ge 6 ]] || die "legacy kubeconfig output is incomplete"
  [[ "${arguments[0]} ${arguments[1]} ${arguments[2]} ${arguments[3]}" == "oci ce cluster create-kubeconfig" ]] || die "legacy kubeconfig output contains an unexpected command"

  OCI_KUBECONFIG_CLUSTER_ID=""
  OCI_KUBECONFIG_ENDPOINT=""
  OCI_KUBECONFIG_LEGACY_FILE=""
  OCI_KUBECONFIG_PROFILE=""
  OCI_KUBECONFIG_REGION=""

  arguments=("${arguments[@]:4}")
  while [[ "${#arguments[@]}" -gt 0 ]]; do
    flag="${arguments[0]}"
    [[ "${#arguments[@]}" -ge 2 ]] || die "legacy kubeconfig output has a flag without a value"
    value="${arguments[1]}"
    arguments=("${arguments[@]:2}")

    case "$flag" in
      --cluster-id)
        OCI_KUBECONFIG_CLUSTER_ID="$value"
        ;;
      --file)
        OCI_KUBECONFIG_LEGACY_FILE="$value"
        ;;
      --kube-endpoint)
        OCI_KUBECONFIG_ENDPOINT="$value"
        ;;
      --profile)
        OCI_KUBECONFIG_PROFILE="$value"
        ;;
      --region)
        OCI_KUBECONFIG_REGION="$value"
        ;;
      --token-version)
        [[ "$value" == "2.0.0" ]] || die "legacy kubeconfig output uses an unsupported token version"
        ;;
      *)
        die "legacy kubeconfig output contains an unexpected flag: ${flag}"
        ;;
    esac
  done

  for argument in OCI_KUBECONFIG_CLUSTER_ID OCI_KUBECONFIG_ENDPOINT OCI_KUBECONFIG_LEGACY_FILE OCI_KUBECONFIG_REGION; do
    [[ -n "${!argument}" ]] || die "legacy kubeconfig output is missing ${argument}"
  done
}

generate_oci_kubeconfig() {
  local terraform_dir="$1"
  local kubeconfig_json
  local kubeconfig_path
  local cluster_name=""
  local arguments

  require_command jq
  require_command oci
  require_command terraform

  if kubeconfig_json="$(terraform -chdir="$terraform_dir" output -json kubeconfig 2>/dev/null)"; then
    OCI_KUBECONFIG_CLUSTER_ID="$(jq -er '.cluster_id' <<<"$kubeconfig_json")"
    OCI_KUBECONFIG_ENDPOINT="$(jq -er '.endpoint' <<<"$kubeconfig_json")"
    OCI_KUBECONFIG_PROFILE="$(jq -r '.profile // ""' <<<"$kubeconfig_json")"
    OCI_KUBECONFIG_REGION="$(jq -er '.region' <<<"$kubeconfig_json")"
    cluster_name="$(jq -er '.cluster_name' <<<"$kubeconfig_json")"
    OCI_KUBECONFIG_LEGACY_FILE=""
  else
    parse_legacy_kubeconfig_output "$(terraform -chdir="$terraform_dir" output -raw kubeconfig_command)"
  fi

  [[ "$OCI_KUBECONFIG_CLUSTER_ID" =~ ^ocid1\.cluster\.[a-z0-9.-]+$ ]] || die "Terraform returned an invalid OCI cluster OCID"
  [[ "$OCI_KUBECONFIG_ENDPOINT" == "PUBLIC_ENDPOINT" || "$OCI_KUBECONFIG_ENDPOINT" == "PRIVATE_ENDPOINT" ]] || die "Terraform returned an invalid kubeconfig endpoint mode"
  [[ "$OCI_KUBECONFIG_REGION" =~ ^[a-z]{2}-[a-z0-9-]+-[0-9]+$ ]] || die "Terraform returned an invalid OCI region"
  [[ -z "$OCI_KUBECONFIG_PROFILE" || "$OCI_KUBECONFIG_PROFILE" =~ ^[A-Za-z0-9_-]+$ ]] || die "Terraform returned an invalid OCI profile"

  if [[ -n "${OCF_KUBECONFIG_PATH:-}" ]]; then
    kubeconfig_path="$OCF_KUBECONFIG_PATH"
  elif [[ -n "$cluster_name" ]]; then
    [[ "$cluster_name" =~ ^[a-z][a-z0-9-]{2,40}$ ]] || die "Terraform returned an invalid cluster name"
    kubeconfig_path="${HOME:?}/.kube/${cluster_name}.yaml"
  else
    kubeconfig_path="$OCI_KUBECONFIG_LEGACY_FILE"
    [[ "$kubeconfig_path" == \~/* ]] && kubeconfig_path="${HOME:?}/${kubeconfig_path#\~/}"
  fi

  [[ "$kubeconfig_path" == /* ]] || die "kubeconfig path must be absolute"
  umask 077
  mkdir -p "$(dirname "$kubeconfig_path")"

  arguments=(
    ce cluster create-kubeconfig
    --cluster-id "$OCI_KUBECONFIG_CLUSTER_ID"
    --file "$kubeconfig_path"
    --region "$OCI_KUBECONFIG_REGION"
    --token-version 2.0.0
    --kube-endpoint "$OCI_KUBECONFIG_ENDPOINT"
  )
  [[ -z "$OCI_KUBECONFIG_PROFILE" ]] || arguments+=(--profile "$OCI_KUBECONFIG_PROFILE")

  log "writing kubeconfig to ${kubeconfig_path}"
  oci "${arguments[@]}"
  printf '%s\n' "$kubeconfig_path"
}
