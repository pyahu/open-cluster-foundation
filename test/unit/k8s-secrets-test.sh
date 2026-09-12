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
    observability-object-storage/LOKI_S3_ENDPOINT)
      printf '%s' "$MOCK_LOKI_S3_ENDPOINT"
      ;;
    observability-object-storage/TEMPO_S3_ENDPOINT)
      printf '%s' "$MOCK_TEMPO_S3_ENDPOINT"
      ;;
    observability-object-storage/S3_REGION)
      printf '%s' "$MOCK_S3_REGION"
      ;;
    observability-object-storage/AWS_ACCESS_KEY_ID)
      printf '%s' "$MOCK_S3_ACCESS_KEY"
      ;;
    observability-object-storage/AWS_SECRET_ACCESS_KEY)
      printf '%s' "$MOCK_S3_SECRET_KEY"
      ;;
    observability-object-storage/TEMPO_S3_BUCKET)
      printf '%s' "$MOCK_TEMPO_BUCKET"
      ;;
    grafana-database/GF_DATABASE_HOST)
      printf '%s' "$MOCK_GRAFANA_DATABASE_HOST"
      ;;
    grafana-database/GF_DATABASE_NAME)
      printf '%s' "$MOCK_GRAFANA_DATABASE_NAME"
      ;;
    grafana-database/GF_DATABASE_USER)
      printf '%s' "$MOCK_GRAFANA_DATABASE_USER"
      ;;
    grafana-database/GF_DATABASE_PASSWORD)
      printf '%s' "$MOCK_GRAFANA_DATABASE_PASSWORD"
      ;;
    grafana-database/GF_SECURITY_SECRET_KEY)
      printf '%s' "$MOCK_GRAFANA_SECURITY_KEY"
      ;;
    grafana-database-ca/ca.crt)
      printf '%s' "$MOCK_GRAFANA_DATABASE_CA"
      ;;
    thanos-object-storage/objstore.yml)
      printf '%s' "$MOCK_THANOS_OBJECT_STORAGE"
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

MOCK_LOKI_S3_ENDPOINT='https://objectstorage.prod.internal'
MOCK_TEMPO_S3_ENDPOINT='objectstorage.prod.internal'
MOCK_S3_REGION='eu-west-production'
MOCK_S3_ACCESS_KEY='production-access-key'
MOCK_S3_SECRET_KEY='production-secret-key'
MOCK_TEMPO_BUCKET='production-tempo'
MOCK_GRAFANA_DATABASE_HOST='postgres.prod.internal:5432'
MOCK_GRAFANA_DATABASE_NAME='grafana'
MOCK_GRAFANA_DATABASE_USER='grafana'
MOCK_GRAFANA_DATABASE_PASSWORD='production-database-password'
MOCK_GRAFANA_SECURITY_KEY='0123456789abcdef0123456789abcdef'
MOCK_GRAFANA_DATABASE_CA=$'-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----'
MOCK_THANOS_OBJECT_STORAGE=$'type: S3\nconfig:\n  bucket: production-thanos\n  endpoint: objectstorage.prod.internal\n  region: eu-west-production\n  access_key: production-access-key\n  secret_key: production-secret-key\n  insecure: false'
validate_durable_observability_inputs

MOCK_LOKI_S3_ENDPOINT='http://objectstorage.prod.internal'
assert_fails validate_durable_observability_inputs
MOCK_LOKI_S3_ENDPOINT='https://objectstorage.prod.internal'
MOCK_TEMPO_S3_ENDPOINT='https://objectstorage.prod.internal'
assert_fails validate_durable_observability_inputs
MOCK_TEMPO_S3_ENDPOINT='objectstorage.prod.internal'
MOCK_GRAFANA_SECURITY_KEY='short'
assert_fails validate_durable_observability_inputs
MOCK_GRAFANA_SECURITY_KEY='0123456789abcdef0123456789abcdef'
MOCK_THANOS_OBJECT_STORAGE=$'type: S3\nconfig:\n  bucket: production-thanos\n  endpoint: objectstorage.prod.internal\n  region: eu-west-production\n  insecure: true'
assert_fails validate_durable_observability_inputs

printf '%s\n' "Kubernetes secret validation unit tests passed"
