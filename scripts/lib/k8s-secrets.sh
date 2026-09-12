#!/usr/bin/env bash

set -Eeuo pipefail

ensure_secret_exists() {
  local namespace="$1"
  local name="$2"
  local help_text="$3"

  kubectl -n "$namespace" get secret "$name" >/dev/null 2>&1 || die "missing secret ${namespace}/${name}. ${help_text}"
}

ensure_secret_key_exists() {
  local namespace="$1"
  local name="$2"
  local key="$3"
  local help_text="$4"
  local value

  value="$(kubectl -n "$namespace" get secret "$name" -o jsonpath="{.data.${key}}" 2>/dev/null || true)"
  [[ -n "$value" ]] || die "secret ${namespace}/${name} is missing key ${key}. ${help_text}"
}

ensure_secret_label_equals() {
  local namespace="$1"
  local name="$2"
  local label="$3"
  local expected="$4"
  local help_text="$5"
  local actual

  actual="$(kubectl -n "$namespace" get secret "$name" -o json | yq -r ".metadata.labels.\"${label}\" // \"\"")"
  [[ "$actual" == "$expected" ]] || die "secret ${namespace}/${name} must have label ${label}=${expected}. ${help_text}"
}

read_secret_value() {
  local namespace="$1"
  local name="$2"
  local key="$3"
  local encoded

  encoded="$(kubectl -n "$namespace" get secret "$name" -o jsonpath="{.data.${key}}")"
  printf '%s' "$encoded" | openssl base64 -d -A
}

prepare_valkey_acl_secret() {
  if ! profile_enabled cache "$ENVIRONMENT" || [[ "$OCF_RESOLVED_CACHE_ACCESS_MODE" != "acl" ]]; then
    return
  fi

  if kubectl -n cache get secret valkey-acl >/dev/null 2>&1; then
    ensure_secret_key_exists cache valkey-acl default "The default ACL user requires a password."
    return
  fi

  if [[ "$OCF_RESOLVED_INSTALL_MODE" != "fresh" ]] || profile_enabled secrets "$ENVIRONMENT"; then
    die "missing secret cache/valkey-acl. Create it with key default and update every cache client before enabling ACL authentication."
  fi

  log "creating Valkey ACL secret"
  kubectl -n cache create secret generic valkey-acl \
    --from-literal="default=$(openssl rand -base64 32)"
}

validate_zitadel_inputs() {
  local masterkey dsn masterkey_length

  ensure_secret_exists identity zitadel-masterkey "Create it before enabling the identity profile."
  ensure_secret_key_exists identity zitadel-masterkey masterkey "ZITADEL requires an immutable 32-byte master key."
  ensure_secret_exists identity zitadel-postgres-dsn "Create it before enabling the identity profile."
  ensure_secret_key_exists identity zitadel-postgres-dsn dsn "ZITADEL requires a PostgreSQL DSN."
  masterkey="$(read_secret_value identity zitadel-masterkey masterkey)"
  dsn="$(read_secret_value identity zitadel-postgres-dsn dsn)"
  masterkey_length="$(printf '%s' "$masterkey" | wc -c | tr -d ' ')"
  [[ "$masterkey_length" -eq 32 ]] || die "secret identity/zitadel-masterkey key masterkey must contain exactly 32 bytes"
  [[ "$dsn" == postgres://* || "$dsn" == postgresql://* ]] || die "secret identity/zitadel-postgres-dsn key dsn must contain a PostgreSQL URI"
  [[ "$dsn" == *sslmode=require* || "$dsn" == *sslmode=verify-ca* || "$dsn" == *sslmode=verify-full* ]] || die "secret identity/zitadel-postgres-dsn key dsn must require TLS"
}

validate_infisical_inputs() {
  local auth_secret encryption_key database_uri redis_url redis_username redis_password site_url trusted_proxy_cidrs decoded_length valkey_password expected_site_url

  ensure_secret_exists secrets infisical-secrets "Create it before enabling the secrets profile."
  for key in AUTH_SECRET ENCRYPTION_KEY REDIS_URL REDIS_USERNAME REDIS_PASSWORD SITE_URL TRUSTED_PROXY_CIDRS; do
    ensure_secret_key_exists secrets infisical-secrets "$key" "Infisical requires this setting."
  done
  ensure_secret_exists secrets infisical-postgres "Create it before enabling the secrets profile."
  ensure_secret_key_exists secrets infisical-postgres connectionString "Infisical requires a PostgreSQL connection string."

  auth_secret="$(read_secret_value secrets infisical-secrets AUTH_SECRET)"
  encryption_key="$(read_secret_value secrets infisical-secrets ENCRYPTION_KEY)"
  redis_url="$(read_secret_value secrets infisical-secrets REDIS_URL)"
  redis_username="$(read_secret_value secrets infisical-secrets REDIS_USERNAME)"
  redis_password="$(read_secret_value secrets infisical-secrets REDIS_PASSWORD)"
  site_url="$(read_secret_value secrets infisical-secrets SITE_URL)"
  trusted_proxy_cidrs="$(read_secret_value secrets infisical-secrets TRUSTED_PROXY_CIDRS)"
  database_uri="$(read_secret_value secrets infisical-postgres connectionString)"

  if ! decoded_length="$(printf '%s' "$auth_secret" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d ' ')"; then
    die "secret secrets/infisical-secrets key AUTH_SECRET must be valid base64"
  fi
  [[ "$decoded_length" -eq 32 ]] || die "secret secrets/infisical-secrets key AUTH_SECRET must encode exactly 32 bytes"
  [[ "$encryption_key" =~ ^[[:xdigit:]]{32}$ ]] || die "secret secrets/infisical-secrets key ENCRYPTION_KEY must contain a random 16-byte hexadecimal value"
  [[ "$site_url" == https://* ]] || die "secret secrets/infisical-secrets key SITE_URL must use https"
  reject_placeholder "$site_url" "SITE_URL in secret secrets/infisical-secrets"
  expected_site_url="https://$(read_yaml_value "${BASE_DIR}/values/local/infisical.yaml" '.platform.hostname')"
  [[ "$site_url" == "$expected_site_url" ]] || die "Infisical SITE_URL must match ${expected_site_url}"
  [[ -n "$trusted_proxy_cidrs" && "$trusted_proxy_cidrs" != *0.0.0.0/0* && "$trusted_proxy_cidrs" != *::/0* ]] || die "secret secrets/infisical-secrets key TRUSTED_PROXY_CIDRS must restrict trusted proxies to the cluster proxy CIDRs"
  [[ "$database_uri" == postgres://* || "$database_uri" == postgresql://* ]] || die "secret secrets/infisical-postgres key connectionString must contain a PostgreSQL URI"
  [[ "$database_uri" == *sslmode=require* || "$database_uri" == *sslmode=verify-ca* || "$database_uri" == *sslmode=verify-full* ]] || die "secret secrets/infisical-postgres key connectionString must require TLS"
  [[ "$redis_url" == "redis://valkey.cache.svc.cluster.local:6379" ]] || die "secret secrets/infisical-secrets key REDIS_URL must use the internal Valkey service without embedded credentials"
  [[ "$redis_username" == "default" ]] || die "secret secrets/infisical-secrets key REDIS_USERNAME must be default"
  valkey_password="$(read_secret_value cache valkey-acl default)"
  [[ "$redis_password" == "$valkey_password" ]] || die "Infisical REDIS_PASSWORD must match cache/valkey-acl key default"
}

check_optional_profile_inputs() {
  if profile_enabled identity "$ENVIRONMENT"; then
    validate_zitadel_inputs
  fi

  if profile_enabled secrets "$ENVIRONMENT"; then
    validate_infisical_inputs
  fi
}

check_identity_inputs() {
  if [[ "$ENVIRONMENT" == "ci" ]]; then
    return
  fi

  if profile_enabled observability "$ENVIRONMENT"; then
    ensure_secret_exists monitoring grafana-oidc-credentials "Create it with the identity provider application credentials: kubectl -n monitoring create secret generic grafana-oidc-credentials --from-literal=client_id=<id> --from-literal=client_secret=<secret>"
    ensure_secret_key_exists monitoring grafana-oidc-credentials client_id "Grafana reads this key through envFromSecrets."
    ensure_secret_key_exists monitoring grafana-oidc-credentials client_secret "Grafana reads this key through envFromSecrets."
  fi

  if [[ "$OCF_RESOLVED_IDENTITY_ACCESS_MODE" == "sso" ]] && profile_enabled gitops "$ENVIRONMENT"; then
    ensure_secret_exists argocd argocd-oidc-credentials "Create it with the identity provider application secret: kubectl -n argocd create secret generic argocd-oidc-credentials --from-literal=clientSecret=<secret>"
    ensure_secret_key_exists argocd argocd-oidc-credentials clientSecret "Argo CD reads this key from oidc.config."
    ensure_secret_label_equals argocd argocd-oidc-credentials app.kubernetes.io/part-of argocd "Argo CD only allows secret references from labeled secrets."
  fi
}
