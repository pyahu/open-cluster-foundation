#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BASE_DIR="${OCF_ROOT}/kubernetes/production-base"
CRD_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

require_command helm
require_command helmfile
require_command kubeconform

profile_enabled kafka starter && die "starter must not enable Kafka"
profile_enabled kafkaConnect starter && die "starter must not enable Kafka Connect"
profile_enabled cache starter && die "starter must not enable Valkey"
profile_enabled postgresOperator starter && die "starter must not enable the PostgreSQL operator"
profile_enabled messagingOperators starter && die "starter must not enable the messaging operator"
profile_enabled postgresOperator production || die "production must enable the PostgreSQL operator"
profile_enabled messagingOperators production || die "production must enable the messaging operator"
profile_enabled kafka production && die "production must not enable Kafka"
profile_enabled cache production && die "production must not enable Valkey"
profile_enabled kafka production-data || die "production-data must enable Kafka"
profile_enabled kafkaConnect production-data || die "production-data must enable Kafka Connect"
profile_enabled cache production-data || die "production-data must enable Valkey"
profile_enabled kafka default || die "default must preserve Kafka for existing installations"
profile_enabled kafkaConnect default || die "default must preserve Kafka Connect for existing installations"
profile_enabled cache default || die "default must preserve Valkey for existing installations"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

for environment in starter production production-data default all-components ci; do
  log "rendering helmfile environment ${environment}"
  (cd "$BASE_DIR" && helmfile -f helmfile.yaml.gotmpl -e "$environment" template) \
    >"${WORK_DIR}/rendered-${environment}.yaml"

  log "validating rendered ${environment} manifests"
  kubeconform -strict -summary \
    -schema-location default \
    -schema-location "$CRD_CATALOG" \
    -ignore-missing-schemas \
    "${WORK_DIR}/rendered-${environment}.yaml"
done

# Static manifests and custom resources are validated without
# -ignore-missing-schemas: every kind used here must have a schema in the
# upstream CRDs catalog, so typos in CRs fail the build.
log "validating static manifests and resources against CRD schemas"
find "${BASE_DIR}/manifests" "${BASE_DIR}/resources" -name '*.yaml' -print0 |
  xargs -0 kubeconform -strict -summary \
    -schema-location default \
    -schema-location "$CRD_CATALOG"

log "kubernetes checks passed"
