#!/usr/bin/env bash

set -Eeuo pipefail

require_instance_values_file() {
  local release="$1"
  local values_file="${BASE_DIR}/values/local/${release}.yaml"

  require_file "$values_file" "Copy values/local-examples/${release}.yaml to values/local/${release}.yaml and replace every placeholder before applying to a non-CI cluster."
}

read_yaml_value() {
  local values_file="$1"
  local expression="$2"

  yq eval -r "${expression} // \"\"" "$values_file"
}

read_yaml_scalar() {
  local values_file="$1"
  local expression="$2"

  yq eval -r "$expression" "$values_file"
}

reject_placeholder() {
  local value="$1"
  local field_name="$2"

  [[ -n "$value" ]] || die "${field_name} must not be empty"

  case "$value" in
    *.example | *.example/* | *.example:* | *example.com* | *example.org* | *example.net* | *replace-me* | *REPLACE_ME* | *'<'* | *'>'*)
      die "${field_name} still contains a placeholder: ${value}"
      ;;
  esac
}

require_https_url() {
  local value="$1"
  local field_name="$2"

  [[ "$value" == https://* ]] || die "${field_name} must use https"
}

require_true() {
  local value="$1"
  local field_name="$2"

  [[ "$value" == "true" ]] || die "${field_name} must be true"
}

require_false() {
  local value="$1"
  local field_name="$2"

  [[ "$value" == "false" ]] || die "${field_name} must be false"
}

require_scope() {
  local scopes="$1"
  local required_scope="$2"
  local field_name="$3"

  [[ " ${scopes} " == *" ${required_scope} "* ]] || die "${field_name} must include ${required_scope}"
}

validate_argocd_sso_values() {
  local values_file="$1"
  local domain="$2"
  local admin_enabled url issuer client_id client_secret expected_client_secret policy_default policy_csv scopes

  admin_enabled="$(read_yaml_scalar "$values_file" '.configs.cm."admin.enabled"')"
  url="$(read_yaml_value "$values_file" '.configs.cm.url')"
  issuer="$(read_yaml_value "$values_file" '.configs.cm."oidc.config" | from_yaml | .issuer')"
  client_id="$(read_yaml_value "$values_file" '.configs.cm."oidc.config" | from_yaml | .clientID')"
  client_secret="$(read_yaml_value "$values_file" '.configs.cm."oidc.config" | from_yaml | .clientSecret')"
  expected_client_secret="\$argocd-oidc-credentials:clientSecret"
  policy_default="$(read_yaml_value "$values_file" '.configs.rbac."policy.default"')"
  policy_csv="$(read_yaml_value "$values_file" '.configs.rbac."policy.csv"')"
  scopes="$(read_yaml_value "$values_file" '.configs.rbac.scopes')"

  reject_placeholder "$url" "configs.cm.url in values/local/argocd.yaml"
  reject_placeholder "$issuer" "OIDC issuer in values/local/argocd.yaml"
  reject_placeholder "$client_id" "OIDC clientID in values/local/argocd.yaml"
  reject_placeholder "$policy_csv" "configs.rbac.policy.csv in values/local/argocd.yaml"
  [[ "$admin_enabled" != "true" ]] || die "configs.cm.admin.enabled must not be true in SSO mode"
  require_https_url "$url" "configs.cm.url in values/local/argocd.yaml"
  require_https_url "$issuer" "OIDC issuer in values/local/argocd.yaml"
  [[ "$url" == "https://${domain}" ]] || die "configs.cm.url must match https://${domain}"
  [[ "$client_secret" == "$expected_client_secret" ]] || die "OIDC clientSecret must reference \$argocd-oidc-credentials:clientSecret"
  CLIENT_ID="$client_id" yq -e '.configs.cm."oidc.config" | from_yaml | (.allowedAudiences // []) | contains([strenv(CLIENT_ID)])' "$values_file" >/dev/null || die "OIDC allowedAudiences must include clientID"
  yq -e '.configs.cm."oidc.config" | from_yaml | (.requestedScopes // []) | contains(["openid"])' "$values_file" >/dev/null || die "OIDC requestedScopes must include openid"
  yq -e '.configs.cm."oidc.config" | from_yaml | (.requestedScopes // []) | contains(["groups"])' "$values_file" >/dev/null || die "OIDC requestedScopes must include groups"
  [[ "$(read_yaml_value "$values_file" '.configs.cm."oidc.config" | from_yaml | .requestedIDTokenClaims.groups.essential')" == "true" ]] || die "OIDC requestedIDTokenClaims.groups.essential must be true"
  [[ "$policy_default" == "role:authenticated" ]] || die "configs.rbac.policy.default must be role:authenticated"
  [[ "$scopes" == *groups* ]] || die "configs.rbac.scopes must include groups"
  grep -Eq '^[[:space:]]*g,[[:space:]]*[^,]+,[[:space:]]*role:admin[[:space:]]*$' <<<"$policy_csv" || die "configs.rbac.policy.csv must map an identity group to role:admin"
  grep -Eq '^[[:space:]]*g,[[:space:]]*[^,]+,[[:space:]]*role:readonly[[:space:]]*$' <<<"$policy_csv" || die "configs.rbac.policy.csv must map an identity group to role:readonly"
}

validate_grafana_sso_values() {
  local values_file="$1"
  local disable_login_form oauth_enabled oauth_scopes use_pkce use_refresh_token role_attribute_strict role_attribute_path allow_assign_grafana_admin

  disable_login_form="$(read_yaml_scalar "$values_file" '.["grafana.ini"].auth.disable_login_form')"
  oauth_enabled="$(read_yaml_scalar "$values_file" '.["grafana.ini"]["auth.generic_oauth"].enabled')"
  oauth_scopes="$(read_yaml_value "$values_file" '.["grafana.ini"]["auth.generic_oauth"].scopes')"
  use_pkce="$(read_yaml_scalar "$values_file" '.["grafana.ini"]["auth.generic_oauth"].use_pkce')"
  use_refresh_token="$(read_yaml_scalar "$values_file" '.["grafana.ini"]["auth.generic_oauth"].use_refresh_token')"
  role_attribute_strict="$(read_yaml_scalar "$values_file" '.["grafana.ini"]["auth.generic_oauth"].role_attribute_strict')"
  role_attribute_path="$(read_yaml_value "$values_file" '.["grafana.ini"]["auth.generic_oauth"].role_attribute_path')"
  allow_assign_grafana_admin="$(read_yaml_scalar "$values_file" '.["grafana.ini"]["auth.generic_oauth"].allow_assign_grafana_admin')"

  require_true "$disable_login_form" "grafana.ini.auth.disable_login_form"
  require_true "$oauth_enabled" "grafana.ini.auth.generic_oauth.enabled"
  require_scope "$oauth_scopes" openid "grafana.ini.auth.generic_oauth.scopes"
  require_scope "$oauth_scopes" groups "grafana.ini.auth.generic_oauth.scopes"
  require_scope "$oauth_scopes" offline_access "grafana.ini.auth.generic_oauth.scopes"
  require_true "$use_pkce" "grafana.ini.auth.generic_oauth.use_pkce"
  require_true "$use_refresh_token" "grafana.ini.auth.generic_oauth.use_refresh_token"
  require_true "$role_attribute_strict" "grafana.ini.auth.generic_oauth.role_attribute_strict"
  require_false "$allow_assign_grafana_admin" "grafana.ini.auth.generic_oauth.allow_assign_grafana_admin"
  [[ "$role_attribute_path" == *'groups['* ]] || die "grafana.ini.auth.generic_oauth.role_attribute_path must derive roles from groups"
  [[ "$role_attribute_path" == *"'Admin'"* && "$role_attribute_path" == *"'Editor'"* && "$role_attribute_path" == *"'Viewer'"* ]] || die "grafana.ini.auth.generic_oauth.role_attribute_path must map explicit Admin, Editor and Viewer groups"
  [[ "$role_attribute_path" == *"'None'" ]] || die "grafana.ini.auth.generic_oauth.role_attribute_path must default to None"
  [[ "$role_attribute_path" != *GrafanaAdmin* ]] || die "grafana.ini.auth.generic_oauth.role_attribute_path must not grant Grafana server administrator"
}

validate_zitadel_values() {
  local values_file="$1"
  local external_secure external_domain api_hostname login_hostname

  external_secure="$(read_yaml_scalar "$values_file" '.zitadel.configmapConfig.ExternalSecure')"
  external_domain="$(read_yaml_value "$values_file" '.zitadel.configmapConfig.ExternalDomain')"
  api_hostname="$(read_yaml_value "$values_file" '.gateway.httpRoute.hostnames[0]')"
  login_hostname="$(read_yaml_value "$values_file" '.login.gateway.httpRoute.hostnames[0]')"
  require_true "$external_secure" "zitadel.configmapConfig.ExternalSecure"
  reject_placeholder "$external_domain" "zitadel.configmapConfig.ExternalDomain in values/local/zitadel.yaml"
  [[ "$api_hostname" == "$external_domain" ]] || die "gateway.httpRoute hostname must match ZITADEL ExternalDomain"
  [[ "$login_hostname" == "$external_domain" ]] || die "login.gateway.httpRoute hostname must match ZITADEL ExternalDomain"
}

validate_infisical_values() {
  local values_file="$1"
  local hostname

  hostname="$(read_yaml_value "$values_file" '.platform.hostname')"
  reject_placeholder "$hostname" "platform.hostname in values/local/infisical.yaml"
}

validate_instance_values() {
  if [[ "$ENVIRONMENT" == "ci" ]]; then
    return
  fi

  if profile_enabled gitops "$ENVIRONMENT"; then
    require_instance_values_file argocd

    local argocd_values="${BASE_DIR}/values/local/argocd.yaml"
    local argocd_domain
    argocd_domain="$(read_yaml_value "$argocd_values" '.global.domain')"
    reject_placeholder "$argocd_domain" "global.domain in values/local/argocd.yaml"

    if [[ "${OCF_RESOLVED_IDENTITY_ACCESS_MODE:-legacy}" == "sso" ]]; then
      validate_argocd_sso_values "$argocd_values" "$argocd_domain"
    fi
  fi

  if profile_enabled observability "$ENVIRONMENT"; then
    require_instance_values_file grafana

    local grafana_values="${BASE_DIR}/values/local/grafana.yaml"
    local root_url auth_url token_url api_url role_attribute_path
    root_url="$(read_yaml_value "$grafana_values" '.["grafana.ini"].server.root_url')"
    auth_url="$(read_yaml_value "$grafana_values" '.["grafana.ini"]["auth.generic_oauth"].auth_url')"
    token_url="$(read_yaml_value "$grafana_values" '.["grafana.ini"]["auth.generic_oauth"].token_url')"
    api_url="$(read_yaml_value "$grafana_values" '.["grafana.ini"]["auth.generic_oauth"].api_url')"
    role_attribute_path="$(read_yaml_value "$grafana_values" '.["grafana.ini"]["auth.generic_oauth"].role_attribute_path')"

    reject_placeholder "$root_url" "grafana.ini.server.root_url in values/local/grafana.yaml"
    reject_placeholder "$auth_url" "grafana.ini.auth.generic_oauth.auth_url in values/local/grafana.yaml"
    reject_placeholder "$token_url" "grafana.ini.auth.generic_oauth.token_url in values/local/grafana.yaml"
    reject_placeholder "$api_url" "grafana.ini.auth.generic_oauth.api_url in values/local/grafana.yaml"
    reject_placeholder "$role_attribute_path" "grafana.ini.auth.generic_oauth.role_attribute_path in values/local/grafana.yaml"

    require_https_url "$root_url" "grafana.ini.server.root_url"
    require_https_url "$auth_url" "grafana.ini.auth.generic_oauth.auth_url"
    require_https_url "$token_url" "grafana.ini.auth.generic_oauth.token_url"
    require_https_url "$api_url" "grafana.ini.auth.generic_oauth.api_url"
    [[ "$role_attribute_path" != "'GrafanaAdmin'" ]] || die "grafana.ini.auth.generic_oauth.role_attribute_path must derive privileges from trusted claims instead of granting GrafanaAdmin to every user"

    if [[ "${OCF_RESOLVED_IDENTITY_ACCESS_MODE:-legacy}" == "sso" ]]; then
      validate_grafana_sso_values "$grafana_values"
    fi
  fi

  if profile_enabled identity "$ENVIRONMENT"; then
    require_instance_values_file zitadel
    validate_zitadel_values "${BASE_DIR}/values/local/zitadel.yaml"
  fi

  if profile_enabled secrets "$ENVIRONMENT"; then
    require_instance_values_file infisical
    validate_infisical_values "${BASE_DIR}/values/local/infisical.yaml"
  fi
}

validate_profile_contract() {
  if profile_enabled kafkaConnect "$ENVIRONMENT" && ! profile_enabled kafka "$ENVIRONMENT"; then
    die "profile kafkaConnect requires profile kafka"
  fi

  if profile_enabled kafka "$ENVIRONMENT" && ! profile_enabled messagingOperators "$ENVIRONMENT"; then
    die "profile kafka requires profile messagingOperators"
  fi

  if profile_enabled secrets "$ENVIRONMENT" && ! profile_enabled cache "$ENVIRONMENT"; then
    die "profile secrets requires profile cache"
  fi
}
