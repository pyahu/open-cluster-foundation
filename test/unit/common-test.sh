#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/../../scripts/lib/common.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

MOCK_SOURCE="${TEST_ROOT}/source"
printf 'verified artifact\n' >"$MOCK_SOURCE"

curl() {
  local destination=""

  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--output" ]]; then
      destination="$2"
      shift 2
      continue
    fi
    shift
  done

  cp "$MOCK_SOURCE" "$destination"
}

expected_sha256="$(sha256_file "$MOCK_SOURCE")"
destination="${TEST_ROOT}/artifact"
download_verified "https://artifacts.example.test/release.yaml" "$expected_sha256" "$destination"
cmp --silent "$MOCK_SOURCE" "$destination"

invalid_destination="${TEST_ROOT}/invalid-artifact"
if (download_verified "https://artifacts.example.test/release.yaml" "$(printf '0%.0s' {1..64})" "$invalid_destination") >/dev/null 2>&1; then
  printf 'checksum mismatch was accepted\n' >&2
  exit 1
fi
[[ ! -e "$invalid_destination" ]]
[[ -z "$(compgen -G "${invalid_destination}.download.*" || true)" ]]

if (download_verified "http://artifacts.example.test/release.yaml" "$expected_sha256" "$invalid_destination") >/dev/null 2>&1; then
  printf 'insecure download URL was accepted\n' >&2
  exit 1
fi

printf 'common library unit tests passed\n'
