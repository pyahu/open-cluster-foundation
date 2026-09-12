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
require_command kustomize
require_command yq

profile_enabled kafka starter && die "starter must not enable Kafka"
profile_enabled kafkaConnect starter && die "starter must not enable Kafka Connect"
profile_enabled cache starter && die "starter must not enable Valkey"
profile_enabled postgresOperator starter && die "starter must not enable the PostgreSQL operator"
profile_enabled messagingOperators starter && die "starter must not enable the messaging operator"
profile_enabled postgresOperator production || die "production must enable the PostgreSQL operator"
profile_enabled messagingOperators production || die "production must enable the messaging operator"
profile_enabled kafka production && die "production must not enable Kafka"
profile_enabled cache production && die "production must not enable Valkey"
profile_enabled kafka production-data || die "production-data must enable Kafka"
profile_enabled kafkaConnect production-data || die "production-data must enable Kafka Connect"
profile_enabled cache production-data || die "production-data must enable Valkey"
profile_enabled kafka default || die "default must preserve Kafka for existing installations"
profile_enabled kafkaConnect default || die "default must preserve Kafka Connect for existing installations"
profile_enabled cache default || die "default must preserve Valkey for existing installations"
profile_enabled highAvailability production-ha || die "production-ha must enable high availability"
profile_enabled durableObservability production-ha || die "production-ha must enable durable observability"
profile_enabled observability production-ha || die "production-ha must enable observability"

for environment in starter production production-data default all-components ci; do
  profile_enabled highAvailability "$environment" && die "${environment} must not implicitly enable high availability"
  profile_enabled durableObservability "$environment" && die "${environment} must not implicitly enable durable observability"
done

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

for environment in starter production production-ha production-data default all-components ci; do
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

PRODUCTION_HA_RENDER="${WORK_DIR}/rendered-production-ha.yaml"
ha_placement_violations="$(yq ea '[
  select(.kind == "Deployment" or .kind == "StatefulSet") |
  select(.spec.replicas > 1) |
  select(
    ([.spec.template.spec.topologySpreadConstraints[]? | select(.topologyKey == "kubernetes.io/hostname" and .whenUnsatisfiable == "DoNotSchedule")] | length == 0) and
    ([.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[]? | select(.topologyKey == "kubernetes.io/hostname")] | length == 0)
  )
] | length' "$PRODUCTION_HA_RENDER")"
[[ "$ha_placement_violations" -eq 0 ]] || die "every replicated production-ha workload must use hard hostname placement"

ha_resource_violations="$(yq ea '[
  select(.kind == "Deployment" or .kind == "StatefulSet") |
  select(.spec.replicas > 1) |
  .spec.template.spec.containers[] |
  select(.resources.requests.cpu == null or .resources.requests.memory == null or .resources.limits.memory == null)
] | length' "$PRODUCTION_HA_RENDER")"
[[ "$ha_resource_violations" -eq 0 ]] || die "every replicated production-ha container must declare CPU and memory requests and a memory limit"

while IFS=$'\t' read -r workload_name; do
  pdb_name="$workload_name"
  [[ "$workload_name" != "loki" ]] || pdb_name="loki-single-binary"
  [[ "$workload_name" != "strimzi-cluster-operator" ]] || pdb_name="strimzi-cluster-operator-pdb"
  pdb_count="$(PDB_NAME="$pdb_name" yq ea '[select(.kind == "PodDisruptionBudget" and .metadata.name == strenv(PDB_NAME))] | length' "$PRODUCTION_HA_RENDER")"
  [[ "$pdb_count" -eq 1 ]] || die "replicated production-ha workload ${workload_name} must have one PodDisruptionBudget"
done < <(yq ea -N -r 'select(.kind == "Deployment" or .kind == "StatefulSet") | select(.spec.replicas > 1) | .metadata.name' "$PRODUCTION_HA_RENDER")

prometheus_replicas="$(yq ea -N 'select(.kind == "Prometheus" and .metadata.name == "kube-prometheus-stack-prometheus") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
alertmanager_replicas="$(yq ea -N 'select(.kind == "Alertmanager" and .metadata.name == "kube-prometheus-stack-alertmanager") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
prometheus_object_storage="$(yq ea -N 'select(.kind == "Prometheus" and .metadata.name == "kube-prometheus-stack-prometheus") | .spec.thanos.objectStorageConfig.name' "$PRODUCTION_HA_RENDER")"
[[ "$prometheus_replicas" -eq 2 ]] || die "production-ha must run two Prometheus replicas"
[[ "$alertmanager_replicas" -eq 3 ]] || die "production-ha must run three Alertmanager replicas"
[[ "$prometheus_object_storage" == "thanos-object-storage" ]] || die "production-ha Prometheus must upload blocks through the Thanos object-storage secret"

loki_replicas="$(yq ea -N 'select(.kind == "StatefulSet" and .metadata.name == "loki") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
tempo_ingester_replicas="$(yq ea -N 'select(.kind == "StatefulSet" and .metadata.name == "tempo-distributed-ingester") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
grafana_replicas="$(yq ea -N 'select(.kind == "Deployment" and .metadata.name == "grafana") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
grafana_config="$(yq ea -N 'select(.kind == "ConfigMap" and .metadata.name == "grafana") | .data."grafana.ini"' "$PRODUCTION_HA_RENDER")"
grafana_datasources="$(yq ea -N 'select(.kind == "ConfigMap" and .metadata.name == "grafana") | .data."datasources.yaml"' "$PRODUCTION_HA_RENDER")"
[[ "$loki_replicas" -eq 3 ]] || die "production-ha must run three Loki replicas"
[[ "$tempo_ingester_replicas" -eq 3 ]] || die "production-ha must run three Tempo ingesters"
[[ "$grafana_replicas" -eq 3 ]] || die "production-ha must run three Grafana replicas"
grep -q '^type = postgres$' <<<"$grafana_config" || die "production-ha Grafana must use PostgreSQL"
grep -q 'thanos-query.monitoring.svc.cluster.local' <<<"$grafana_datasources" || die "production-ha Grafana must query Prometheus data through Thanos"

thanos_query_replicas="$(yq ea -N 'select(.kind == "Deployment" and .metadata.name == "thanos-query") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
thanos_store_replicas="$(yq ea -N 'select(.kind == "StatefulSet" and .metadata.name == "thanos-store") | .spec.replicas' "$PRODUCTION_HA_RENDER")"
thanos_query_args="$(yq ea -N -r 'select(.kind == "Deployment" and .metadata.name == "thanos-query") | .spec.template.spec.containers[0].args[]' "$PRODUCTION_HA_RENDER")"
thanos_query_endpoints="$(yq ea -N -r 'select(.kind == "ConfigMap" and .metadata.name == "thanos-query-endpoints") | .data."endpoints.yaml"' "$PRODUCTION_HA_RENDER")"
[[ "$thanos_query_replicas" -eq 3 && "$thanos_store_replicas" -eq 3 ]] || die "production-ha must run three Thanos Query and Store replicas"
grep -q '^--endpoint.sd-config-file=' <<<"$thanos_query_args" || die "Thanos Query must use the endpoint service-discovery configuration"
if grep -Eq '^--endpoint(-group)?=' <<<"$thanos_query_args"; then
  die "Thanos Query must not use deprecated endpoint flags"
fi
grep -q 'kube-prometheus-stack-thanos-discovery.monitoring.svc.cluster.local:10901' <<<"$thanos_query_endpoints" || die "Thanos Query must discover Prometheus sidecars"
grep -q 'thanos-store.monitoring.svc.cluster.local:10901' <<<"$thanos_query_endpoints" || die "Thanos Query must discover object-store gateways"

# Static manifests and custom resources are validated without
# -ignore-missing-schemas: every kind used here must have a schema in the
# upstream CRDs catalog, so typos in CRs fail the build.
log "validating static manifests and resources against CRD schemas"
find "${BASE_DIR}/manifests" "${BASE_DIR}/resources" -name '*.yaml' -print0 |
  xargs -0 kubeconform -strict -summary \
    -schema-location default \
    -schema-location "$CRD_CATALOG"

cnpg_manifests=()
while IFS= read -r -d '' manifest; do
  cnpg_manifests+=("$manifest")
done < <(find "${BASE_DIR}/resources" -name '*.yaml' -print0)
cnpg_cluster_count="$(yq ea '[select(.apiVersion == "postgresql.cnpg.io/v1" and .kind == "Cluster")] | length' "${cnpg_manifests[@]}")"
cnpg_scheduling_violations="$(yq ea '[
  select(.apiVersion == "postgresql.cnpg.io/v1" and .kind == "Cluster") |
  select(
    .spec.affinity.nodeSelector."open-cluster-foundation.io/workload" != "database" or
    .spec.affinity.enablePodAntiAffinity != true or
    .spec.affinity.podAntiAffinityType != "preferred" or
    .spec.affinity.topologyKey != "kubernetes.io/hostname" or
    ([
      (.spec.affinity.tolerations // [])[] |
      select(
        .key == "workload.open-cluster-foundation.io/database" and
        .operator == "Equal" and
        .value == "true" and
        .effect == "NoSchedule"
      )
    ] | length) != 1
  )
] | length' "${cnpg_manifests[@]}")"

[[ "$cnpg_cluster_count" -gt 0 ]] || die "no CloudNativePG cluster examples found"
[[ "$cnpg_scheduling_violations" -eq 0 ]] || die "CloudNativePG examples must follow the database scheduling contract"

gateway_manifests=(
  "${BASE_DIR}/manifests/gateway.yaml"
  "${BASE_DIR}/resources/cert-manager/gateway-https-listener.yaml"
)
gateway_listener_count="$(yq ea '[select(.apiVersion == "gateway.networking.k8s.io/v1" and .kind == "Gateway") | .spec.listeners[]] | length' "${gateway_manifests[@]}")"
gateway_access_violations="$(yq ea '[
  select(.apiVersion == "gateway.networking.k8s.io/v1" and .kind == "Gateway") |
  .spec.listeners[] |
  select(
    .allowedRoutes.namespaces.from != "Selector" or
    .allowedRoutes.namespaces.selector.matchLabels."open-cluster-foundation.io/gateway-access" != "public"
  )
] | length' "${gateway_manifests[@]}")"

[[ "$gateway_listener_count" -gt 0 ]] || die "no Gateway listeners found"
[[ "$gateway_access_violations" -eq 0 ]] || die "Gateway listeners must restrict routes to labeled namespaces"

for namespace in platform-system argocd monitoring identity secrets; do
  access="$(yq ea "select(.kind == \"Namespace\" and .metadata.name == \"${namespace}\") | .metadata.labels.\"open-cluster-foundation.io/gateway-access\"" "${BASE_DIR}/manifests/namespace-baseline.yaml")"
  [[ "$access" == "public" ]] || die "base route namespace ${namespace} must be allowed to attach public routes"
done

trusted_observability_namespaces="$(yq ea -o=json -I=0 '[select(.kind == "Namespace" and .metadata.labels."open-cluster-foundation.io/observability-access" == "true") | .metadata.name] | sort' "${BASE_DIR}/manifests/namespace-baseline.yaml")"
expected_observability_namespaces="$(yq -o=json -I=0 '[.managedNamespaces[] | select(. != "default")] | sort' "${BASE_DIR}/charts/network-policies/values.yaml")"
[[ "$trusted_observability_namespaces" == "$expected_observability_namespaces" ]] || die "trusted observability namespaces must match managed namespaces except default"

PROMETHEUS_RENDER="${WORK_DIR}/rendered-ci.yaml"
SECURE_IDENTITY_RENDER="${WORK_DIR}/rendered-starter.yaml"
argocd_admin_enabled="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "argocd-cm") | .data."admin.enabled"' "$SECURE_IDENTITY_RENDER")"
argocd_default_role="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm") | .data."policy.default"' "$SECURE_IDENTITY_RENDER")"
secure_grafana_config="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "grafana") | .data."grafana.ini"' "$SECURE_IDENTITY_RENDER")"
[[ "$argocd_admin_enabled" == "false" ]] || die "fresh Argo CD installations must disable the local admin"
[[ "$argocd_default_role" == "role:authenticated" ]] || die "fresh Argo CD installations must not grant read access by default"
grep -q '^disable_login_form = true$' <<<"$secure_grafana_config" || die "fresh Grafana installations must disable the login form"
grep -q '^use_pkce = true$' <<<"$secure_grafana_config" || die "fresh Grafana installations must enable PKCE"
grep -q '^use_refresh_token = true$' <<<"$secure_grafana_config" || die "fresh Grafana installations must enable refresh tokens"
grep -q '^role_attribute_strict = true$' <<<"$secure_grafana_config" || die "fresh Grafana installations must require an explicit role mapping"
grep -q '^allow_assign_grafana_admin = false$' <<<"$secure_grafana_config" || die "fresh Grafana installations must reject OAuth server-admin assignment"
if grep -q GrafanaAdmin <<<"$secure_grafana_config"; then
  die "fresh Grafana installations must not grant server administrator through OAuth"
fi

LEGACY_IDENTITY_RENDER="${WORK_DIR}/legacy-identity.yaml"
(cd "$BASE_DIR" && OCF_IDENTITY_ACCESS_MODE=legacy helmfile -f helmfile.yaml.gotmpl -e starter template --selector name=argocd --selector name=grafana) >"$LEGACY_IDENTITY_RENDER"
legacy_argocd_admin_enabled="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "argocd-cm") | .data."admin.enabled"' "$LEGACY_IDENTITY_RENDER")"
legacy_argocd_default_role="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm") | .data."policy.default"' "$LEGACY_IDENTITY_RENDER")"
legacy_grafana_config="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "grafana") | .data."grafana.ini"' "$LEGACY_IDENTITY_RENDER")"
[[ "$legacy_argocd_admin_enabled" == "true" ]] || die "legacy Argo CD mode must preserve the local admin"
[[ "$legacy_argocd_default_role" == "role:readonly" ]] || die "legacy Argo CD mode must preserve default read access"
grep -q '^disable_login_form = false$' <<<"$legacy_grafana_config" || die "legacy Grafana mode must preserve the login form"
grep -q "^role_attribute_path = 'GrafanaAdmin'$" <<<"$legacy_grafana_config" || die "legacy Grafana mode must preserve the former role mapping"
grep -q '^allow_assign_grafana_admin = true$' <<<"$legacy_grafana_config" || die "legacy Grafana mode must preserve OAuth server-admin assignment"

valkey_strategy="$(yq ea 'select(.kind == "Deployment" and .metadata.name == "valkey") | .spec.strategy.type' "$PROMETHEUS_RENDER")"
valkey_pvc_retention="$(yq ea 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "valkey") | .metadata.annotations."helm.sh/resource-policy"' "$PROMETHEUS_RENDER")"
valkey_config="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "valkey-config") | .data."valkey.conf"' "$PROMETHEUS_RENDER")"
valkey_acl_mount_count="$(yq ea '[select(.kind == "Deployment" and .metadata.name == "valkey") | .spec.template.spec.volumes[] | select(.secret.secretName == "valkey-acl")] | length' "$PROMETHEUS_RENDER")"
[[ "$valkey_strategy" == "Recreate" ]] || die "standalone Valkey must use Recreate with a ReadWriteOnce volume"
[[ "$valkey_pvc_retention" == "keep" ]] || die "Valkey must retain its PVC on Helm uninstall"
[[ "$valkey_acl_mount_count" -eq 1 ]] || die "fresh Valkey installations must mount the external ACL secret"
grep -q '^appendonly yes$' <<<"$valkey_config" || die "Valkey must enable append-only persistence"
grep -q '^appendfsync everysec$' <<<"$valkey_config" || die "Valkey must persist the append-only log every second"

LEGACY_VALKEY_RENDER="${WORK_DIR}/legacy-valkey.yaml"
(cd "$BASE_DIR" && OCF_CACHE_ACCESS_MODE=legacy helmfile -f helmfile.yaml.gotmpl -e ci template --selector name=valkey) >"$LEGACY_VALKEY_RENDER"
legacy_valkey_acl_mount_count="$(yq ea '[select(.kind == "Deployment" and .metadata.name == "valkey") | .spec.template.spec.volumes[]? | select(.secret.secretName == "valkey-acl")] | length' "$LEGACY_VALKEY_RENDER")"
[[ "$legacy_valkey_acl_mount_count" -eq 0 ]] || die "legacy Valkey mode must preserve unauthenticated access"

OPTIONAL_COMPONENTS_RENDER="${WORK_DIR}/rendered-all-components.yaml"
optional_deployment_violations="$(yq ea '[
  select(.kind == "Deployment" and (.metadata.name == "zitadel" or .metadata.name == "zitadel-login" or .metadata.name == "infisical-infisical-standalone-infisical")) |
  select(
    .spec.replicas < 2 or
    .spec.template.spec.automountServiceAccountToken != false or
    .spec.template.spec.securityContext.runAsNonRoot != true or
    .spec.template.spec.securityContext.seccompProfile.type != "RuntimeDefault" or
    .spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation != false or
    .spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem != true or
    .spec.template.spec.containers[0].resources.requests.cpu == null or
    .spec.template.spec.containers[0].resources.requests.memory == null or
    .spec.template.spec.containers[0].resources.limits.cpu == null or
    .spec.template.spec.containers[0].resources.limits.memory == null
  )
] | length' "$OPTIONAL_COMPONENTS_RENDER")"
[[ "$optional_deployment_violations" -eq 0 ]] || die "ZITADEL and Infisical deployments must use hardened, resourced, replicated pods"
optional_pdb_count="$(yq ea '[select(.kind == "PodDisruptionBudget" and (.metadata.name == "zitadel" or .metadata.name == "zitadel-login" or .metadata.name == "infisical"))] | length' "$OPTIONAL_COMPONENTS_RENDER")"
[[ "$optional_pdb_count" -eq 3 ]] || die "ZITADEL and Infisical must render disruption budgets"
optional_route_count="$(yq ea '[select(.kind == "HTTPRoute" and (.metadata.name == "zitadel" or .metadata.name == "zitadel-login" or .metadata.name == "infisical"))] | length' "$OPTIONAL_COMPONENTS_RENDER")"
[[ "$optional_route_count" -eq 3 ]] || die "ZITADEL and Infisical must render Gateway API routes"

for selector in serviceMonitorNamespaceSelector podMonitorNamespaceSelector ruleNamespaceSelector probeNamespaceSelector scrapeConfigNamespaceSelector; do
  selector_value="$(yq ea "select(.kind == \"Prometheus\") | .spec.${selector}.matchLabels.\"open-cluster-foundation.io/observability-access\"" "$PROMETHEUS_RENDER")"
  [[ "$selector_value" == "true" ]] || die "Prometheus ${selector} must require the trusted namespace label"
done

probe_selector="$(yq ea 'select(.kind == "Prometheus") | .spec.probeSelector.matchLabels."open-cluster-foundation.io/probe"' "$PROMETHEUS_RENDER")"
scrape_config_selector="$(yq ea 'select(.kind == "Prometheus") | .spec.scrapeConfigSelector.matchLabels."open-cluster-foundation.io/scrape-config"' "$PROMETHEUS_RENDER")"
[[ "$probe_selector" == "trusted" ]] || die "Prometheus probes must require the trusted resource label"
[[ "$scrape_config_selector" == "trusted" ]] || die "Prometheus scrape configs must require the trusted resource label"

example_probe_label="$(yq '.metadata.labels."open-cluster-foundation.io/probe"' "${BASE_DIR}/resources/monitoring/probes.yaml.example")"
[[ "$example_probe_label" == "trusted" ]] || die "the Probe example must opt in to trusted discovery"

grafana_role_count="$(yq ea '[select(.kind == "Role" and .metadata.name == "grafana" and .metadata.namespace == "monitoring")] | length' "$PROMETHEUS_RENDER")"
grafana_cluster_role_count="$(yq ea '[select(.kind == "ClusterRole" and .metadata.name == "grafana")] | length' "$PROMETHEUS_RENDER")"
grafana_dashboard_namespace="$(yq ea 'select(.kind == "Deployment" and .metadata.name == "grafana") | .spec.template.spec.containers[] | select(.name == "grafana-sc-dashboard") | .env[] | select(.name == "NAMESPACE") | .value' "$PROMETHEUS_RENDER")"
[[ "$grafana_role_count" -eq 1 && "$grafana_cluster_role_count" -eq 0 ]] || die "Grafana dashboard discovery must use namespaced RBAC"
[[ "$grafana_dashboard_namespace" == "monitoring" ]] || die "Grafana dashboard discovery must stay in monitoring"

strimzi_dashboard_count="$(yq ea '[select(.kind == "ConfigMap" and .metadata.labels.grafana_dashboard == "1" and .metadata.name | test("^strimzi-"))] | length' "$PROMETHEUS_RENDER")"
strimzi_dashboard_violations="$(yq ea '[select(.kind == "ConfigMap" and .metadata.labels.grafana_dashboard == "1" and .metadata.name | test("^strimzi-")) | select(.metadata.namespace != "monitoring")] | length' "$PROMETHEUS_RENDER")"
[[ "$strimzi_dashboard_count" -gt 0 ]] || die "Strimzi dashboards were not rendered"
[[ "$strimzi_dashboard_violations" -eq 0 ]] || die "Strimzi dashboards must be created in monitoring"

trusted_alloy_config="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "alloy") | .data."config.alloy"' "$PROMETHEUS_RENDER")"
grep -q 'open-cluster-foundation.io/telemetry-client=trusted' <<<"$trusted_alloy_config" || die "trusted Alloy discovery must require the telemetry client label"
grep -q 'names = \["platform-system"' <<<"$trusted_alloy_config" || die "trusted Alloy discovery must enumerate foundation namespaces"

LEGACY_ALLOY_RENDER="${WORK_DIR}/legacy-alloy.yaml"
(cd "$BASE_DIR" && OCF_OBSERVABILITY_SCOPE=legacy helmfile -f helmfile.yaml.gotmpl -e ci template --selector name=alloy) >"$LEGACY_ALLOY_RENDER"
legacy_alloy_config="$(yq ea 'select(.kind == "ConfigMap" and .metadata.name == "alloy") | .data."config.alloy"' "$LEGACY_ALLOY_RENDER")"
if grep -q 'open-cluster-foundation.io/telemetry-client=trusted' <<<"$legacy_alloy_config"; then
  die "legacy Alloy discovery must preserve cluster-wide log collection"
fi

NETWORK_POLICY_CHART="${BASE_DIR}/charts/network-policies"
NETWORK_POLICY_RENDER="${WORK_DIR}/network-policies.yaml"
helm lint "${BASE_DIR}/charts/infisical-platform"
helm lint "$NETWORK_POLICY_CHART"
helm lint "${BASE_DIR}/charts/thanos"
helm lint "${BASE_DIR}/charts/production-ha-policies"
helm template ocf-network-policies "$NETWORK_POLICY_CHART" \
  --namespace platform-system >"$NETWORK_POLICY_RENDER"
kubeconform -strict -summary "$NETWORK_POLICY_RENDER"

HA_NETWORK_POLICY_RENDER="${WORK_DIR}/production-ha-network-policies.yaml"
helm template ocf-network-policies "$NETWORK_POLICY_CHART" \
  --namespace platform-system \
  --set 'grafanaDatabaseCidrs={10.20.30.40/32,2001:db8::/64}' >"$HA_NETWORK_POLICY_RENDER"
kubeconform -strict -summary "$HA_NETWORK_POLICY_RENDER"
grafana_database_policy_cidrs="$(yq ea -o=json -I=0 'select(.kind == "NetworkPolicy" and .metadata.name == "ocf-grafana-database") | [.spec.egress[0].to[].ipBlock.cidr] | sort' "$HA_NETWORK_POLICY_RENDER")"
[[ "$grafana_database_policy_cidrs" == '["10.20.30.40/32","2001:db8::/64"]' ]] || die "production-ha must restrict Grafana PostgreSQL egress to configured CIDRs"

declared_managed_namespaces="$(yq -o=json -I=0 '.managedNamespaces | sort' "${NETWORK_POLICY_CHART}/values.yaml")"
labeled_managed_namespaces="$(yq ea -o=json -I=0 '[select(.kind == "Namespace" and .metadata.labels."open-cluster-foundation.io/network-policy" == "managed") | .metadata.name] | sort' "${BASE_DIR}/manifests/namespace-baseline.yaml")"
[[ "$declared_managed_namespaces" == "$labeled_managed_namespaces" ]] || die "NetworkPolicy chart namespaces must match managed namespace labels"

network_policy_count="$(yq ea '[select(.apiVersion == "networking.k8s.io/v1" and .kind == "NetworkPolicy")] | length' "$NETWORK_POLICY_RENDER")"
[[ "$network_policy_count" -ge 20 ]] || die "expected at least 20 rendered NetworkPolicies"

api_server_policy_count="$(yq ea '[
  select(.kind == "NetworkPolicy" and .metadata.name == "ocf-baseline") |
  select([.spec.egress[].ports[]? | select(.protocol == "TCP" and .port == 6443)] | length > 0)
] | length' "$NETWORK_POLICY_RENDER")"
managed_namespace_count="$(yq '.managedNamespaces | length' "${NETWORK_POLICY_CHART}/values.yaml")"
[[ "$api_server_policy_count" -eq "$managed_namespace_count" ]] || die "every baseline policy must allow the Kubernetes API server port"

observability_identity_count="$(yq ea '[
  select(.kind == "NetworkPolicy" and .metadata.name == "ocf-observability-ingestion") |
  .spec.ingress[].from[] |
  select(
    .namespaceSelector.matchLabels."open-cluster-foundation.io/observability-access" == "true" and
    .podSelector.matchLabels."open-cluster-foundation.io/telemetry-client" == "trusted"
  )
] | length' "$NETWORK_POLICY_RENDER")"
[[ "$observability_identity_count" -eq 1 ]] || die "observability ingestion must require trusted namespace and workload identity"

LEGACY_NETWORK_POLICY_RENDER="${WORK_DIR}/legacy-network-policies.yaml"
helm template ocf-network-policies "$NETWORK_POLICY_CHART" \
  --namespace platform-system \
  --set observability.requireWorkloadIdentity=false >"$LEGACY_NETWORK_POLICY_RENDER"
legacy_observability_identity_count="$(yq ea '[
  select(.kind == "NetworkPolicy" and .metadata.name == "ocf-observability-ingestion") |
  .spec.ingress[].from[] |
  select(has("podSelector"))
] | length' "$LEGACY_NETWORK_POLICY_RENDER")"
[[ "$legacy_observability_identity_count" -eq 0 ]] || die "legacy observability policies must preserve namespace-only ingestion"

log "kubernetes checks passed"
