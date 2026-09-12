#!/usr/bin/env bash

set -Eeuo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCF_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

source "${OCF_ROOT}/scripts/lib/common.sh"
source "${OCF_ROOT}/scripts/lib/k8s-config.sh"

BASE_DIR=""
ENVIRONMENT="default"

assert_fails() {
  if ("$@") >/dev/null 2>&1; then
    die "expected command to fail: $*"
  fi
}

assert_succeeds() {
  local output
  if ! output="$("$@" 2>&1)"; then
    printf '%s\n' "$output" >&2
    die "expected command to succeed: $*"
  fi
}

require_command yq

for environment in starter production production-data default all-components ci; do
  ENVIRONMENT="$environment"
  assert_succeeds validate_profile_contract
done
ENVIRONMENT=default

assert_fails reject_placeholder "" field
assert_fails reject_placeholder "https://grafana.example.com" field
assert_fails reject_placeholder "https://grafana.cluster.example" field
assert_fails reject_placeholder "replace-me" field
assert_succeeds reject_placeholder "https://grafana.prod.internal" field

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
BASE_DIR="$WORK_DIR"
mkdir -p "${BASE_DIR}/values/local"

assert_fails require_instance_values_file grafana
touch "${BASE_DIR}/values/local/grafana.yaml"
assert_succeeds require_instance_values_file grafana

ENVIRONMENT="ci"
assert_succeeds validate_instance_values

ENVIRONMENT="default"
OCF_RESOLVED_IDENTITY_ACCESS_MODE="legacy"
assert_fails validate_instance_values

printf '%s\n' \
  'global:' \
  '  domain: argocd.prod.internal' \
  >"${BASE_DIR}/values/local/argocd.yaml"

printf '%s\n' \
  'grafana.ini:' \
  '  server:' \
  '    root_url: https://grafana.cluster.example' \
  '  auth.generic_oauth:' \
  '    auth_url: https://identity.cluster.example/authorize' \
  '    token_url: https://identity.cluster.example/token' \
  '    api_url: https://identity.cluster.example/userinfo' \
  "    role_attribute_path: \"'GrafanaAdmin'\"" \
  >"${BASE_DIR}/values/local/grafana.yaml"

assert_fails validate_instance_values

printf '%s\n' \
  'grafana.ini:' \
  '  server:' \
  '    root_url: https://grafana.prod.internal' \
  '  auth.generic_oauth:' \
  '    auth_url: https://identity.prod.internal/authorize' \
  '    token_url: https://identity.prod.internal/token' \
  '    api_url: https://identity.prod.internal/userinfo' \
  "    role_attribute_path: \"contains(groups[*], 'grafana-admin') && 'GrafanaAdmin' || 'Viewer'\"" \
  >"${BASE_DIR}/values/local/grafana.yaml"

assert_succeeds validate_instance_values

OCF_RESOLVED_IDENTITY_ACCESS_MODE="sso"
assert_fails validate_instance_values

cat >"${BASE_DIR}/values/local/argocd.yaml" <<'EOF'
global:
  domain: argocd.prod.internal
configs:
  cm:
    admin.enabled: false
    url: https://argocd.prod.internal
    oidc.config: |
      name: OIDC
      issuer: https://identity.prod.internal
      clientID: argocd-production
      clientSecret: $argocd-oidc-credentials:clientSecret
      allowedAudiences:
        - argocd-production
      requestedScopes:
        - openid
        - profile
        - email
        - groups
      requestedIDTokenClaims:
        groups:
          essential: true
  rbac:
    policy.default: role:authenticated
    policy.csv: |
      g, platform-argocd-admins, role:admin
      g, platform-argocd-readonly, role:readonly
    scopes: '[groups]'
EOF

cat >"${BASE_DIR}/values/local/grafana.yaml" <<'EOF'
grafana.ini:
  server:
    root_url: https://grafana.prod.internal
  auth:
    disable_login_form: true
  auth.generic_oauth:
    enabled: true
    scopes: openid profile email groups offline_access
    auth_url: https://identity.prod.internal/authorize
    token_url: https://identity.prod.internal/token
    api_url: https://identity.prod.internal/userinfo
    use_pkce: true
    use_refresh_token: true
    role_attribute_strict: true
    role_attribute_path: contains(groups[*], 'platform-grafana-admins') && 'Admin' || contains(groups[*], 'platform-grafana-editors') && 'Editor' || contains(groups[*], 'platform-grafana-viewers') && 'Viewer' || 'None'
    allow_assign_grafana_admin: false
EOF

assert_succeeds validate_instance_values

sed -i.bak "s/allow_assign_grafana_admin: false/allow_assign_grafana_admin: true/" "${BASE_DIR}/values/local/grafana.yaml"
rm "${BASE_DIR}/values/local/grafana.yaml.bak"
assert_fails validate_instance_values

printf '%s\n' "k8s production base unit tests passed"
