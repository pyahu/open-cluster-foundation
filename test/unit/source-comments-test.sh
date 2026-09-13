#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_SCRIPT="$(cd "${TEST_DIR}/../.." && pwd)/scripts/ci-source-comments.sh"
FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

git -C "$FIXTURE_ROOT" init -q
printf '%s\n' '#!/usr/bin/env bash' '# shellcheck source=lib/common.sh' 'case value in' '  *) exit 0 ;;' 'esac' >"${FIXTURE_ROOT}/clean.sh"
printf '%s\n' '*.tfstate' '*.key' >"${FIXTURE_ROOT}/.gitignore"
printf '%s\n' '# renovate: datasource=docker depName=example/image' 'image: example/image:1.0.0' >"${FIXTURE_ROOT}/versions.yaml"
printf '%s\n' '# This file is maintained automatically by "terraform init".' '# Manual edits may be lost in future updates.' >"${FIXTURE_ROOT}/.terraform.lock.hcl"
printf '%s\n' 'locals { endpoint = "https://example.com" }' >"${FIXTURE_ROOT}/clean.tf"
git -C "$FIXTURE_ROOT" add .

OCF_COMMENT_SCAN_ROOT="$FIXTURE_ROOT" "$POLICY_SCRIPT" >/dev/null

printf '%s\n' '# forbidden' 'key: value' >"${FIXTURE_ROOT}/forbidden.yaml"
git -C "$FIXTURE_ROOT" add forbidden.yaml

if OCF_COMMENT_SCAN_ROOT="$FIXTURE_ROOT" "$POLICY_SCRIPT" >/dev/null 2>&1; then
  printf '%s\n' "source comment policy accepted a forbidden comment" >&2
  exit 1
fi

printf '%s%s\n' 'key: value ' '# forbidden' >"${FIXTURE_ROOT}/forbidden.yaml"
git -C "$FIXTURE_ROOT" add forbidden.yaml

if OCF_COMMENT_SCAN_ROOT="$FIXTURE_ROOT" "$POLICY_SCRIPT" >/dev/null 2>&1; then
  printf '%s\n' "source comment policy accepted a forbidden inline comment" >&2
  exit 1
fi

printf '%s\n' 'key: value' >"${FIXTURE_ROOT}/forbidden.yaml"
printf '%s%s\n' 'locals { enabled = true } ' '// forbidden' >"${FIXTURE_ROOT}/forbidden.tf"
git -C "$FIXTURE_ROOT" add forbidden.yaml forbidden.tf

if OCF_COMMENT_SCAN_ROOT="$FIXTURE_ROOT" "$POLICY_SCRIPT" >/dev/null 2>&1; then
  printf '%s\n' "source comment policy accepted a forbidden slash comment" >&2
  exit 1
fi

printf '%s\n' "source comment policy tests passed"
