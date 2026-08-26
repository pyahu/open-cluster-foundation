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

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

for environment in default all-components ci; do
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
