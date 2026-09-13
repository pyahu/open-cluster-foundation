# Kubernetes Production Base

A practical Kubernetes foundation for community clusters. It installs the edge,
certificate, GitOps, database-operator, messaging-operator and observability
layers that many teams need before running real workloads.

This module is provider-agnostic and starts after Terraform. It assumes you
already have a reachable Kubernetes cluster, a default StorageClass, working
DNS and enough node capacity for stateful workloads.

This is a starting point, not a production guarantee. Review every value file
against your cloud provider, security model, budget, backup policy and on-call
capacity before using it for critical systems.

## Component versions

Versions are pinned in [`versions.yaml`](versions.yaml). The complete
[component reference](../../docs/reference/components.md) is generated from
that catalog and local chart metadata; CI rejects manual drift. For Helm-based
components, the application version is the version shipped by the pinned chart.
This blueprint does not override chart images merely to force a newer binary
outside the chart's tested path.

Prometheus is installed by kube-prometheus-stack. Do not install a second
Prometheus instance unless you intentionally want a separate monitoring plane.

## What Gets Automated

The main automation entrypoint is [`helmfile.yaml.gotmpl`](helmfile.yaml.gotmpl).
It reads [`versions.yaml`](versions.yaml), installs pinned Helm releases and
uses environment profiles from [`environments/`](environments).

An automatic fresh installation selects `starter`. Existing installations
that predate installation state select the compatibility-only `default`
environment, so an upgrade does not remove or disable services that are
already running.

The generated [compatibility reference](../../docs/reference/compatibility.md)
lists every environment and its exact enabled profiles.

The starter environment enables:

- Envoy Gateway, cert-manager and Argo CD.
- kube-prometheus-stack, Loki, Tempo, Grafana, Alloy and Reloader, plus
  curated Grafana dashboards and PrometheusRules for Kafka, CloudNativePG,
  Loki and cert-manager.
- Edge and synthetic monitoring: Envoy proxy and Envoy Gateway scrape
  targets, per-route request, error and latency rules, and the blackbox
  exporter for Probe resources (availability, latency and certificate expiry
  of your public endpoints). Start from
  [`resources/monitoring/probes.yaml.example`](resources/monitoring/probes.yaml.example).
- Correlated signals: Tempo's metrics generator writes span metrics and the
  service graph to Prometheus, Prometheus keeps exemplars, and the Grafana
  datasources link logs to traces, traces to logs and metrics, and metric
  exemplars to traces.

### Log parsing is opt-in per pod

In the trusted observability scope, Alloy collects every container log from
OCF-managed namespaces. An application Pod is collected only when its namespace
has `open-cluster-foundation.io/observability-access=true` and its Pod template
has `open-cluster-foundation.io/telemetry-client=trusted`. Annotate a collected
Pod to have its output parsed:

| Annotation `logging.open-cluster-foundation.io/format` | What Alloy does |
| --- | --- |
| `java` | Keeps a stack trace in one entry with the line that raised it, and turns the level of the Spring Boot / Logback default layout into a `level` label. |
| `json` | Reads `log.level` into a `level` label and `trace.id` / `span.id` into structured metadata, which the Loki datasource links to Tempo. |

Parsing is not applied by default because a multiline rule glues the lines of
any other log format onto the previous entry.

### Alert routing

The base routes every alert to the `null` receiver: nothing pages until you
say where. Receivers, retention and routes go in the instance layer; start
from [`values/local-examples/kube-prometheus-stack.yaml`](values/local-examples/kube-prometheus-stack.yaml),
which routes application namespaces to one receiver and the rest of what
pages (`warning` and `critical`) to another, reading credentials from a
mounted Secret. `info` alerts never page.

The Platform folder in Grafana has a Capacity dashboard (node memory and CPU
in use and requested, namespaces, volumes, OOM kills, restarts) and an Alerts
dashboard (what fires now and over time). Grafana's Alerting page also reads
Alertmanager, so silences can be set from there.

### Instance settings

Retention, alert receivers and anything else specific to one cluster go in
`values/local/<release>.yaml` (gitignored), which helmfile layers on top of
the base values for `argocd`, `kube-prometheus-stack`, `loki`, `tempo`,
`alloy`, `grafana`, `zitadel` and `infisical` when the file exists.

Argo CD and Grafana contain public-domain and identity-provider settings that
must never fall back to repository placeholders on a real cluster. Before a
non-CI apply, create both required local files:

```sh
mkdir -p values/local
cp values/local-examples/argocd.yaml values/local/argocd.yaml
cp values/local-examples/grafana.yaml values/local/grafana.yaml
${EDITOR:-vi} values/local/argocd.yaml values/local/grafana.yaml
```

The apply preflight rejects missing files, placeholder domains, non-HTTPS
identity endpoints, incomplete OIDC claims or audiences, permissive RBAC and
Grafana role expressions that grant server administrator access. Rendering and
CI do not require private instance values.

The installer distinguishes fresh, legacy and state-managed targets before it
applies anything. The full contract, explicit `--mode` controls and environment
change gate are documented in
[`docs/compatibility.md`](../../docs/compatibility.md).

Fresh installations also enforce default-deny ingress and egress across every
OCF-managed namespace after the components become ready. Existing clusters
preserve their current network behavior until an operator follows the staged
[NetworkPolicy migration](../../docs/compatibility.md#networkpolicy-migration)
and passes `--network-policies enforce`. Application namespaces opt into the
minimum platform, observability and Gateway paths with separate labels.

Fresh installations also restrict observability discovery and ingestion.
Existing installations retain cluster-wide discovery until the staged
[observability trust migration](../../docs/compatibility.md#observability-trust-migration)
is selected with `--observability-scope trusted`. The installation state keeps
the chosen scope across later automatic upgrades.

Fresh installations use SSO-only access for Argo CD and Grafana. Argo CD's
local administrator and Grafana's login form are disabled, identities without
an explicit group mapping receive no application access, and Grafana OAuth
cannot assign server administrator. Existing installations retain their former
access behavior until the staged
[identity access migration](../../docs/compatibility.md#identity-access-migration)
is selected with `--identity-access sso`.

Fresh installations that enable Valkey use ACL authentication, append-only
persistence and a retained PVC. The installer creates a random ACL Secret for
a fresh cache unless Infisical is enabled, in which case the shared credential
must be prepared explicitly. Existing installations keep unauthenticated
access until the staged
[cache access migration](../../docs/compatibility.md#cache-access-migration)
is selected with `--cache-access acl`.

Select `production` to add database and messaging operators without creating
application data. Select `production-data` only after reviewing Kafka and
Valkey capacity, storage and recovery requirements. The `all-components`
environment also enables ZITADEL, Infisical and the RabbitMQ operators; do not
run it until their database, master key and application secrets are created.

Select `production-ha` only after completing the
[HA prerequisites and migration procedure](../../docs/production-ha.md) and
the [capacity and cost review](../../docs/capacity-planning.md). It requires
three eligible nodes across at least two zones, external PostgreSQL for Grafana
and S3-compatible storage for Prometheus, Loki and Tempo. The profile is
explicitly opt-in and does not alter compatibility upgrades.

The `production-data`, `default`, `all-components` and `ci` environments also
apply:

- [`resources/kafka/kafka-cluster.yaml`](resources/kafka/kafka-cluster.yaml)
- [`resources/kafka/kafka-connect.yaml`](resources/kafka/kafka-connect.yaml)

Other stateful resources are available, but are not automatic defaults:

- [`resources/cnpg/postgres-with-backup.yaml`](resources/cnpg/postgres-with-backup.yaml)
- [`resources/rabbitmq/rabbitmq-cluster.yaml`](resources/rabbitmq/rabbitmq-cluster.yaml)
- [`resources/kafka/kafka-connect-debezium-postgres.yaml`](resources/kafka/kafka-connect-debezium-postgres.yaml)
- [`resources/zitadel/postgres.yaml`](resources/zitadel/postgres.yaml)
- [`resources/infisical/postgres.yaml`](resources/infisical/postgres.yaml)

## 0. Requirements

```sh
kubectl version --client
helm version
helmfile --version
HELM_DIFF_REPOSITORY="$(yq -r '.components.helmDiff.repository' versions.yaml)"
HELM_DIFF_COMMIT="$(yq -r '.components.helmDiff.commit' versions.yaml)"
helm plugin install "$HELM_DIFF_REPOSITORY" --version "$HELM_DIFF_COMMIT" --verify=false
```

Cluster requirements:

- A Kubernetes version allowed by the generated
  [compatibility reference](../../docs/reference/compatibility.md).
- At least one default StorageClass.
- A CNI that supports NetworkPolicy.
- Nodes spread across failure domains if you plan to run replicated stateful
  services.
- HTTPS egress to GitHub, chart repositories, image registries and object
  storage.
- A real DNS zone for public routes.

## 1. Preflight

```sh
kubectl cluster-info
kubectl get nodes -o wide
kubectl get storageclass
kubectl auth can-i '*' '*' --all-namespaces
```

Fix failed preflight checks before installing add-ons.

## 2. Create Namespaces

From the repository root:

```sh
cd kubernetes/production-base
kubectl apply -f manifests/namespace-baseline.yaml
kubectl get ns -L pod-security.kubernetes.io/enforce
```

The `monitoring` namespace is intentionally `privileged` because node exporters
and collectors commonly need host access. Other namespaces start with
`restricted` or `baseline` Pod Security Admission labels.

## 3. Install Prometheus Operator CRDs

Several charts in this base (cert-manager, Argo CD, ...) ship ServiceMonitors
and fail to install on a fresh cluster before these CRDs exist:

```sh
source ../../scripts/lib/common.sh
PROMETHEUS_CRDS="$(mktemp)"
download_verified \
  "$(component_value prometheusOperatorCrds manifest)" \
  "$(component_value prometheusOperatorCrds manifestSha256)" \
  "$PROMETHEUS_CRDS"
kubectl apply --server-side -f "$PROMETHEUS_CRDS"
rm -f "$PROMETHEUS_CRDS"
```

The Gateway API CRDs are NOT installed here: they ship with the Envoy Gateway
chart (experimental channel) and upgrade in lockstep with it.

## 4. Install Envoy Gateway, Then cert-manager

Envoy Gateway comes first because it owns the Gateway API CRDs, which
cert-manager's Gateway integration requires at startup. cert-manager comes
before the RabbitMQ topology operator, which uses its webhook certificates.

```sh
helmfile -e production apply --selector profile=edge
helmfile -e production apply --selector profile=certificates

kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
```

Create Let's Encrypt issuers after replacing the email address:

```sh
cp resources/cert-manager/cluster-issuers.yaml /tmp/cluster-issuers.yaml
${EDITOR:-vi} /tmp/cluster-issuers.yaml
kubectl apply -f /tmp/cluster-issuers.yaml
```

Start with `letsencrypt-staging`. Switch production routes to
`letsencrypt-prod` only after the staging certificate flow works.

## 5. Install RabbitMQ Operators

RabbitMQ publishes versioned release manifests for its Kubernetes operators.

```sh
source ../../scripts/lib/common.sh
for COMPONENT in rabbitmqClusterOperator rabbitmqMessagingTopologyOperator; do
  MANIFEST="$(mktemp)"
  download_verified \
    "$(component_value "$COMPONENT" manifest)" \
    "$(component_value "$COMPONENT" manifestSha256)" \
    "$MANIFEST"
  kubectl apply --server-side -f "$MANIFEST"
  rm -f "$MANIFEST"
done

kubectl -n rabbitmq-system get deploy
```

The resource RabbitMQ cluster is applied later, after storage and sizing are
reviewed.

## 6. Create Bootstrap Secrets

Grafana uses an existing Secret instead of a password in values:

```sh
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 32)"
```

Grafana also reads its OIDC client from a Secret (`envFromSecrets`); the
keys are the env vars `grafana.ini` expands. Without it the Grafana pod does
not start:

```sh
kubectl -n monitoring create secret generic grafana-oidc-credentials \
  --from-literal=client_id="<oidc-application-client-id>" \
  --from-literal=client_secret="<oidc-application-client-secret>"
```

Argo CD reads its OIDC client secret through a labeled Secret. The client ID,
issuer, audience, scopes and group mappings remain in the local values file:

```sh
kubectl -n argocd create secret generic argocd-oidc-credentials \
  --from-literal=clientSecret="<oidc-application-client-secret>"
kubectl -n argocd label secret argocd-oidc-credentials \
  app.kubernetes.io/part-of=argocd
```

The public URLs, issuer endpoints, client identifiers and authorization groups
in the local examples are placeholders. Copy both example files into
`values/local/` and replace every placeholder. These gitignored files are
layered on top of committed values so instance-specific names never reach Git.
The Grafana file follows this shape:

```yaml
# kubernetes/production-base/values/local/grafana.yaml
grafana.ini:
  server:
    root_url: https://grafana.example.com
  auth.generic_oauth:
    name: ZITADEL
    scopes: openid profile email groups offline_access urn:zitadel:iam:org:id:<org-id>
    auth_url: https://<issuer>/oauth/v2/authorize
    token_url: https://<issuer>/oauth/v2/token
    api_url: https://<issuer>/oidc/v1/userinfo
    use_pkce: true
    use_refresh_token: true
    role_attribute_strict: true
    role_attribute_path: contains(groups[*], '<admin-group>') && 'Admin' || contains(groups[*], '<editor-group>') && 'Editor' || contains(groups[*], '<viewer-group>') && 'Viewer' || 'None'
    allow_assign_grafana_admin: false
```

The remaining secrets in this section are only required when applying the
related add-on resources.

Create Object Storage/S3 credentials before applying CNPG backup resources:

```sh
kubectl -n data create secret generic cnpg-object-store \
  --from-literal=ACCESS_KEY_ID="<object-store-access-key>" \
  --from-literal=SECRET_ACCESS_KEY="<object-store-secret-key>"
```

Create a registry pull/push secret before using the Debezium Kafka Connect
build resource:

```sh
kubectl -n messaging create secret docker-registry registry-credentials \
  --docker-server=registry.example.com \
  --docker-username="<username>" \
  --docker-password="<password>"
```

For the Debezium resource, database credentials are mounted through a
KafkaConnect template volume at `/mnt/app-postgres` and read with the file
config provider:

```sh
cat > /tmp/app-postgres-connector.properties <<'EOF'
username=app
password=replace-me
EOF

kubectl -n messaging create secret generic app-postgres-connector \
  --from-file=app.properties=/tmp/app-postgres-connector.properties

rm -f /tmp/app-postgres-connector.properties
```

## 7. Install The Selected Foundation

When using the repository automation, this step is handled by:

```sh
mise run k8s:base:apply -- --yes
```

For a manual installation from this directory:

```sh
helmfile -e production apply

kubectl apply -f manifests/gateway.yaml
```

Wait for the main controllers:

```sh
kubectl -n envoy-gateway-system rollout status deploy/envoy-gateway --timeout=180s
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n cnpg-system rollout status deploy/cloudnative-pg --timeout=180s
kubectl -n strimzi-system rollout status deploy/strimzi-cluster-operator --timeout=180s
kubectl -n monitoring get pods
kubectl -n reloader get pods
```

To opt in to Kafka and Kafka Connect after reviewing their production sizing,
use the `production-data` environment through the repository automation, or
apply the resources manually:

```sh
kubectl apply -f resources/kafka/kafka-cluster.yaml
kubectl -n messaging wait --for=condition=Ready kafka/foundation-kafka --timeout=1200s

kubectl apply -f resources/kafka/kafka-connect.yaml
kubectl -n messaging wait --for=condition=Ready kafkaconnect/foundation-connect --timeout=900s
```

On OCI, front Envoy Gateway with a Network Load Balancer (layer-4, free,
source-IP preserving) BEFORE pointing DNS — switching load balancer type later
replaces the load balancer and its public IP. Fill in the load balancer NSG
OCID from the foundation outputs, then:

```sh
cp resources/oci/envoyproxy-nlb.yaml /tmp/envoyproxy-nlb.yaml
# Edit the oci-network-security-groups annotation with the LB NSG OCID.
kubectl apply -f /tmp/envoyproxy-nlb.yaml
```

Point your public DNS records to the load balancer created for Envoy Gateway.
The base Gateway starts with HTTP so cert-manager can solve ACME HTTP-01.
Then adapt
[`resources/cert-manager/gateway-https-listener.yaml`](resources/cert-manager/gateway-https-listener.yaml)
with your domains and apply it. It upgrades the Gateway with one HTTPS
listener per concrete hostname and adds a permanent HTTP-to-HTTPS redirect.
The listeners accept routes only from namespaces labeled
`open-cluster-foundation.io/gateway-access=public`. Label each application
namespace deliberately; do not grant the label cluster-wide. Existing
Gateways remain unchanged during automated upgrades. Follow the staged
[Gateway migration](../../docs/compatibility.md#gateway-route-attachment-migration)
before changing an existing private Gateway manifest from `All` to `Selector`.

ACME HTTP-01 cannot issue wildcard certificates. Keep one listener per
hostname, or configure a
[DNS-01 solver](https://cert-manager.io/docs/configuration/acme/dns01/) for
your DNS provider before switching to a single `*.your-domain` listener.

## 8. Apply Stateful Resources

Review every resource before applying it. Storage size, backup bucket, endpoint,
replica count and resource requests must match your environment.

Every CloudNativePG example targets nodes labeled
`open-cluster-foundation.io/workload=database` and tolerates only
`workload.open-cluster-foundation.io/database=true:NoSchedule`. The OCI
foundation instance template creates a compatible two-node database pool. For
an existing OCI pool, run `mise run k8s:nodes:taint-database -- --yes` once.
For another provider, configure at least two nodes with the same label and
taint before applying a database resource. The pod anti-affinity is preferred,
not required, so a three-instance cluster remains schedulable on the default
two-node pool while replicas still spread whenever capacity exists.

CloudNativePG with physical backup and PITR through the Barman Cloud plugin
(the in-tree `barmanObjectStore` backup is deprecated since CNPG 1.26). On OCI,
use the S3 Compatibility API endpoint
(`https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`) with a
Customer Secret Key:

```sh
cp resources/cnpg/postgres-with-backup.yaml /tmp/postgres-with-backup.yaml
# Edit destinationPath, endpointURL, storage and database names.
kubectl apply -f /tmp/postgres-with-backup.yaml
kubectl -n data get objectstores.barmancloud.cnpg.io,clusters.postgresql.cnpg.io,scheduledbackups.postgresql.cnpg.io
```

CloudNativePG restore from object storage:

```sh
cp resources/cnpg/restore-from-backup.yaml /tmp/restore-from-backup.yaml
# Edit destinationPath, endpointURL and serverName (the source cluster name).
kubectl apply -f /tmp/restore-from-backup.yaml
```

Logical `pg_dump` and `pg_restore` workflow:

```sh
sed -n '1,220p' resources/cnpg/logical-dump-restore.md
```

RabbitMQ:

```sh
kubectl apply -f resources/rabbitmq/rabbitmq-cluster.yaml
kubectl -n messaging get rabbitmqclusters.rabbitmq.com
```

Kafka Connect with Debezium:

```sh
cp resources/kafka/kafka-connect-debezium-postgres.yaml /tmp/kafka-connect-debezium.yaml
# Edit registry image, database host, database name and table include list.
kubectl apply -f /tmp/kafka-connect-debezium.yaml
kubectl -n messaging get kafkaconnect,kafkaconnector
```

## 9. Optional ZITADEL

ZITADEL is disabled by default. It needs PostgreSQL and an immutable 32-byte
master key. The production defaults run three API pods and three login pods,
spread them across nodes, reserve CPU and memory, enforce restricted container
security and protect both Deployments with disruption budgets.

Create a database:

```sh
kubectl apply -f resources/zitadel/postgres.yaml
kubectl -n identity get clusters.postgresql.cnpg.io
```

Create the required secrets:

```sh
kubectl -n identity create secret generic zitadel-masterkey \
  --from-literal=masterkey="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)"

kubectl -n identity create secret generic zitadel-postgres-dsn \
  --from-literal=dsn="postgres://zitadel:<password>@zitadel-postgres-rw.identity.svc.cluster.local:5432/zitadel?sslmode=require"
```

Create the private instance layer and replace every placeholder:

```sh
cp values/local-examples/zitadel.yaml values/local/zitadel.yaml
${EDITOR:-vi} values/local/zitadel.yaml
```

The instance Gateway must have an HTTPS listener named `https-auth` for this
hostname. Then enable the profile:

```sh
helmfile -e all-components apply --selector profile=identity
```

## 10. Optional Infisical

Infisical is disabled by default. It uses a CloudNativePG database and the
base Valkey service instead of the chart's hidden single-node Postgres and
Redis subcharts. OCF runs two application replicas with resource bounds,
anti-affinity, restricted containers, no service-account token and a
disruption budget.

Create a database:

```sh
kubectl apply -f resources/infisical/postgres.yaml
kubectl -n secrets get clusters.postgresql.cnpg.io
```

Create one cache password and store it both in the Valkey ACL Secret and in
the Infisical application Secret. Keeping the password outside `REDIS_URL`
prevents it from appearing in diagnostic URLs:

```sh
VALKEY_PASSWORD="$(openssl rand -base64 32)"
kubectl -n cache create secret generic valkey-acl \
  --from-literal=default="$VALKEY_PASSWORD"

kubectl -n secrets create secret generic infisical-secrets \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -hex 16)" \
  --from-literal=AUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=REDIS_URL="redis://valkey.cache.svc.cluster.local:6379" \
  --from-literal=REDIS_USERNAME="default" \
  --from-literal=REDIS_PASSWORD="$VALKEY_PASSWORD" \
  --from-literal=SITE_URL="https://secrets.example.com" \
  --from-literal=TRUSTED_PROXY_CIDRS="<cluster-pod-cidr>"

unset VALKEY_PASSWORD

kubectl -n secrets create secret generic infisical-postgres \
  --from-literal=connectionString="postgresql://infisical:<password>@infisical-postgres-rw.secrets.svc.cluster.local:5432/infisical?sslmode=require"
```

`TRUSTED_PROXY_CIDRS` must cover the Envoy data-plane Pod addresses, not the
whole internet. Create the private domain layer:

```sh
cp values/local-examples/infisical.yaml values/local/infisical.yaml
${EDITOR:-vi} values/local/infisical.yaml
```

The instance Gateway must have an HTTPS listener named `https-infisical` for
this hostname. Then enable the profile:

```sh
helmfile -e all-components apply --selector profile=secrets
```

## 11. Smoke Tests

```sh
kubectl get gatewayclass envoy
kubectl -n platform-system get gateway public-gateway
kubectl get crd | grep -E 'cert-manager.io|gateway.networking.k8s.io|postgresql.cnpg.io|rabbitmq.com|kafka.strimzi.io|monitoring.coreos.com'
kubectl -n argocd get deploy
kubectl -n cnpg-system get deploy
kubectl -n rabbitmq-system get deploy
kubectl -n strimzi-system get deploy
kubectl -n monitoring get pods
kubectl get ns -L pod-security.kubernetes.io/enforce
```

Also test:

- Issue a Let's Encrypt staging certificate.
- Route a demo HTTPRoute through Envoy Gateway.
- Create and restore a CNPG backup.
- Run a logical `pg_dump` restore in a non-production namespace.
- Publish and consume a RabbitMQ message.
- Produce and consume a Kafka message.
- Build the Kafka Connect Debezium image and verify connector status.
- Confirm Grafana has Prometheus, Loki and Tempo datasources.

## Operations Checklist

- Replace `example.com`, registry paths, bucket names and object storage
  endpoints before applying resources.
- Loki retains 14 days of logs on its persistent volume by default. Move Loki
  and Tempo to object storage before high-volume use; see
  [`values/loki-oci-object-storage.example.yaml`](values/loki-oci-object-storage.example.yaml)
  for OCI.
- Configure Alertmanager receivers and escalation rules; the PrometheusRules
  under [`resources/monitoring`](resources/monitoring) fire nowhere until a
  receiver exists.
- Verify SSO group mappings and require MFA for Argo CD, Grafana, ZITADEL and
  Infisical.
- Test physical backup restore and logical dump restore.
- Define upgrade windows for Kubernetes, operators and charts.
- Pin application manifests in Git and let Argo CD reconcile them after the
  initial bootstrap.

## Official References

- Gateway API: <https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/>
- Envoy Gateway Helm install: <https://gateway.envoyproxy.io/docs/install/install-helm/>
- cert-manager Helm install: <https://cert-manager.io/docs/installation/helm/>
- Argo CD Helm chart: <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>
- Argo CD user management and external Secret references: <https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/>
- CloudNativePG installation and backup: <https://cloudnative-pg.io/documentation/current/>
- RabbitMQ Cluster Operator: <https://www.rabbitmq.com/kubernetes/operator/operator-overview>
- Strimzi documentation: <https://strimzi.io/documentation/>
- Debezium documentation: <https://debezium.io/documentation/>
- ZITADEL Kubernetes deployment: <https://zitadel.com/docs/self-hosting/deploy/kubernetes>
- ZITADEL configuration: <https://zitadel.com/docs/self-hosting/deploy/kubernetes/configuration>
- Infisical Kubernetes deployment: <https://infisical.com/docs/self-hosting/deployment-options/kubernetes-helm>
- Infisical environment variables: <https://infisical.com/docs/self-hosting/configuration/envars>
- kube-prometheus-stack: <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- Grafana Helm charts: <https://github.com/grafana-community/helm-charts>
- Grafana Generic OAuth: <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/>
- Kubernetes dashboards (dotdc): <https://github.com/dotdc/grafana-dashboards-kubernetes>
- CNPG Barman Cloud plugin: <https://cloudnative-pg.io/plugin-barman-cloud/>
- Valkey Helm chart: <https://github.com/valkey-io/valkey-helm>
- Kubernetes Pod Security Standards: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
