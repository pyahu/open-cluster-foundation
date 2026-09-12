#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../../scripts/lib/common.sh"
# shellcheck source=scripts/lib/oci.sh
source "${SCRIPT_DIR}/../../scripts/lib/oci.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

TERRAFORM_MODE="structured"
TERRAFORM_STRUCTURED_OUTPUT='{"cluster_id":"ocid1.cluster.oc1.eu-lisbon-1.example","cluster_name":"example-prod","endpoint":"PRIVATE_ENDPOINT","profile":"EXAMPLE_PROFILE","region":"eu-lisbon-1"}'
TERRAFORM_LEGACY_OUTPUT='oci ce cluster create-kubeconfig --cluster-id ocid1.cluster.oc1.eu-lisbon-1.legacy --file ~/.kube/legacy.yaml --region eu-lisbon-1 --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT'
OCI_CALLS="${TEST_ROOT}/oci-calls"
export OCF_KUBECONFIG_PATH="${TEST_ROOT}/generated/kubeconfig.yaml"

terraform() {
  if [[ "$*" == *"output -json kubeconfig"* ]]; then
    [[ "$TERRAFORM_MODE" == "structured" ]] || return 1
    printf '%s\n' "$TERRAFORM_STRUCTURED_OUTPUT"
    return
  fi

  printf '%s\n' "$TERRAFORM_LEGACY_OUTPUT"
}

oci() {
  printf '%s\n' "$*" >>"$OCI_CALLS"
}

structured_path="$(generate_oci_kubeconfig "${TEST_ROOT}/terraform")"
[[ "$structured_path" == *"${OCF_KUBECONFIG_PATH}" ]]
[[ "$(<"$OCI_CALLS")" == "ce cluster create-kubeconfig --cluster-id ocid1.cluster.oc1.eu-lisbon-1.example --file ${OCF_KUBECONFIG_PATH} --region eu-lisbon-1 --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT --profile EXAMPLE_PROFILE" ]]

rm "$OCI_CALLS"
TERRAFORM_STRUCTURED_OUTPUT='{"cluster_id":"ocid1.cluster.oc1.eu-lisbon-1.no-profile","cluster_name":"no-profile-prod","endpoint":"PRIVATE_ENDPOINT","profile":null,"region":"eu-lisbon-1"}'
generate_oci_kubeconfig "${TEST_ROOT}/terraform" >/dev/null
[[ "$(<"$OCI_CALLS")" == "ce cluster create-kubeconfig --cluster-id ocid1.cluster.oc1.eu-lisbon-1.no-profile --file ${OCF_KUBECONFIG_PATH} --region eu-lisbon-1 --token-version 2.0.0 --kube-endpoint PRIVATE_ENDPOINT" ]]

rm "$OCI_CALLS"
TERRAFORM_MODE="legacy"
legacy_path="$(generate_oci_kubeconfig "${TEST_ROOT}/terraform")"
[[ "$legacy_path" == *"${OCF_KUBECONFIG_PATH}" ]]
[[ "$(<"$OCI_CALLS")" == "ce cluster create-kubeconfig --cluster-id ocid1.cluster.oc1.eu-lisbon-1.legacy --file ${OCF_KUBECONFIG_PATH} --region eu-lisbon-1 --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT" ]]

rm "$OCI_CALLS"
TERRAFORM_LEGACY_OUTPUT='oci ce cluster create-kubeconfig --cluster-id ocid1.cluster.oc1.eu-lisbon-1.legacy --file ~/.kube/legacy.yaml --region eu-lisbon-1 --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT; touch /tmp/unsafe'
if (generate_oci_kubeconfig "${TEST_ROOT}/terraform") >/dev/null 2>&1; then
  printf 'unsafe legacy kubeconfig output was accepted\n' >&2
  exit 1
fi
[[ ! -e "$OCI_CALLS" ]]

printf 'OCI unit tests passed\n'
