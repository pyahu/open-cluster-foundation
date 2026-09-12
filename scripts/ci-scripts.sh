#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_command shellcheck

log "running shellcheck"
shellcheck -x --source-path="${OCF_ROOT}/scripts" \
  "${OCF_ROOT}"/scripts/*.sh "${OCF_ROOT}"/scripts/lib/*.sh \
  "${OCF_ROOT}"/test/unit/*.sh

log "running shell unit tests"
for test_script in "${OCF_ROOT}"/test/unit/*.sh; do
  "$test_script"
done

log "script checks passed"
