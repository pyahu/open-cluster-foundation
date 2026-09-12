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

    [[ "$root_url" == https://* ]] || die "grafana.ini.server.root_url must use https"
    [[ "$auth_url" == https://* ]] || die "grafana.ini.auth.generic_oauth.auth_url must use https"
    [[ "$token_url" == https://* ]] || die "grafana.ini.auth.generic_oauth.token_url must use https"
    [[ "$api_url" == https://* ]] || die "grafana.ini.auth.generic_oauth.api_url must use https"
    [[ "$role_attribute_path" != "'GrafanaAdmin'" ]] || die "grafana.ini.auth.generic_oauth.role_attribute_path must derive privileges from trusted claims instead of granting GrafanaAdmin to every user"
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
