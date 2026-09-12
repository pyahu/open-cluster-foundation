#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCF_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

source "${OCF_ROOT}/scripts/lib/common.sh"
source "${OCF_ROOT}/scripts/lib/k8s-config.sh"
source "${OCF_ROOT}/scripts/lib/k8s-secrets.sh"

assert_fails() {
  if ("$@") >/dev/null 2>&1; then
    die "expected command to fail: $*"
  fi
}

ensure_secret_exists() {
  return
}

ensure_secret_key_exists() {
  return
}

read_secret_value() {
  case "$2/$3" in
    zitadel-masterkey/masterkey)
      printf '%s' "$MOCK_ZITADEL_MASTERKEY"
      ;;
    zitadel-postgres-dsn/dsn)
      printf '%s' "$MOCK_ZITADEL_DSN"
      ;;
    infisical-secrets/AUTH_SECRET)
      printf '%s' "$MOCK_INFISICAL_AUTH_SECRET"
      ;;
    infisical-secrets/ENCRYPTION_KEY)
      printf '%s' "$MOCK_INFISICAL_ENCRYPTION_KEY"
      ;;
    infisical-secrets/REDIS_URL)
      printf '%s' "$MOCK_INFISICAL_REDIS_URL"
      ;;
    infisical-secrets/REDIS_USERNAME)
      printf '%s' "$MOCK_INFISICAL_REDIS_USERNAME"
      ;;
    infisical-secrets/REDIS_PASSWORD)
      printf '%s' "$MOCK_INFISICAL_REDIS_PASSWORD"
      ;;
    infisical-secrets/SITE_URL)
      printf '%s' "$MOCK_INFISICAL_SITE_URL"
      ;;
    infisical-secrets/TRUSTED_PROXY_CIDRS)
      printf '%s' "$MOCK_INFISICAL_TRUSTED_PROXY_CIDRS"
      ;;
    infisical-postgres/connectionString)
      printf '%s' "$MOCK_INFISICAL_DATABASE_URI"
      ;;
    valkey-acl/default)
      printf '%s' "$MOCK_VALKEY_PASSWORD"
      ;;
    *)
      die "unexpected mock secret: $2/$3"
      ;;
  esac
}

MOCK_ZITADEL_MASTERKEY=0123456789abcdefghijklmnopqrstuv
MOCK_ZITADEL_DSN='postgresql://zitadel:password@postgres.internal:5432/zitadel?sslmode=require'
validate_zitadel_inputs
MOCK_ZITADEL_MASTERKEY=short
assert_fails validate_zitadel_inputs
MOCK_ZITADEL_MASTERKEY=0123456789abcdefghijklmnopqrstuv
MOCK_ZITADEL_DSN='postgresql://zitadel:password@postgres.internal:5432/zitadel?sslmode=disable'
assert_fails validate_zitadel_inputs

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BASE_DIR="$WORK_DIR"
mkdir -p "${BASE_DIR}/values/local"
printf '%s\n' 'platform:' '  hostname: secrets.prod.internal' >"${BASE_DIR}/values/local/infisical.yaml"

MOCK_INFISICAL_AUTH_SECRET="$(printf '0123456789abcdefghijklmnopqrstuv' | openssl base64 -A)"
MOCK_INFISICAL_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef
MOCK_INFISICAL_REDIS_URL='redis://valkey.cache.svc.cluster.local:6379'
MOCK_INFISICAL_REDIS_USERNAME=default
MOCK_INFISICAL_REDIS_PASSWORD=cache-password
MOCK_INFISICAL_SITE_URL='https://secrets.prod.internal'
MOCK_INFISICAL_TRUSTED_PROXY_CIDRS='10.244.0.0/16'
MOCK_INFISICAL_DATABASE_URI='postgresql://infisical:password@postgres.internal:5432/infisical?sslmode=require'
MOCK_VALKEY_PASSWORD=cache-password
validate_infisical_inputs

MOCK_INFISICAL_ENCRYPTION_KEY=short
assert_fails validate_infisical_inputs
MOCK_INFISICAL_ENCRYPTION_KEY=0123456789abcdef0123456789abcdef
MOCK_INFISICAL_TRUSTED_PROXY_CIDRS='0.0.0.0/0'
assert_fails validate_infisical_inputs
MOCK_INFISICAL_TRUSTED_PROXY_CIDRS='10.244.0.0/16'
MOCK_INFISICAL_REDIS_PASSWORD=wrong
assert_fails validate_infisical_inputs

printf '%s\n' "Kubernetes secret validation unit tests passed"
