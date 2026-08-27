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

## Component Matrix

Versions were checked against upstream releases and Helm indexes on
`2026-06-26` and are pinned in [`versions.yaml`](versions.yaml).
For Helm-based components, the pinned app version is the version supported by
the latest non-deprecated chart. This blueprint does not override chart images
to force a newer binary outside the chart's tested path.

| Component | Install method | Pinned version | Default |
| --- | --- | --- | --- |
| Gateway API | Bundled with the Envoy Gateway chart | `v1.5.1` | Yes |
| Prometheus Operator CRDs | Upstream release manifest | `v0.92.0` | Yes |
| Envoy Gateway | OCI Helm chart | chart/app `v1.8.1` | Yes |
| cert-manager | Helm chart | chart/app `v1.20.3` | Yes |
| Argo CD | Helm chart | chart `9.7.1`, app `v3.4.4` | Yes |
| CloudNativePG | Helm chart | chart `0.28.3`, app `1.29.1` | Yes |
| RabbitMQ Cluster Operator | Upstream release manifest | `v2.21.1` | Yes |
| RabbitMQ Messaging Topology Operator | Upstream release manifest | `v1.19.3` | Yes |
| Strimzi Kafka Operator | Helm chart | chart/app `1.0.1` | Yes |
| Kafka | Strimzi custom resource | `4.2.0` | Yes |
| Kafka Connect | Strimzi custom resource | `4.2.0` | Yes |
| Debezium Postgres connector | Strimzi plugin artifact | `3.5.2.Final` | Add-on resource |
| ZITADEL | Helm chart | chart `10.0.4`, app `v4.15.3` | Optional |
| Infisical | Helm chart | chart `1.9.0`, image `v0.161.8` | Optional |
| kube-prometheus-stack | Helm chart | chart `87.2.1`, Prometheus `v3.12.0` | Yes |
| Loki | Helm chart | chart `18.1.1`, app `3.7.3` | Yes |
| Tempo | Helm chart | chart `2.2.3`, app `2.10.7` | Yes |
| Grafana | Helm chart | chart `12.7.1`, app `13.1.0` | Yes |
| Grafana Alloy | Helm chart | chart `1.10.0`, app `v1.17.0` | Yes |
| Stakater Reloader | Helm chart | chart `2.2.12`, app `v1.4.17` | Yes |
| Valkey | Helm chart | chart `0.10.0`, app `9.1.0` | Yes |
| CNPG Barman Cloud plugin | Upstream release manifest | `v0.13.0` | Yes |

Prometheus is installed by kube-prometheus-stack. Do not install a second
Prometheus instance unless you intentionally want a separate monitoring plane.

## What Gets Automated

The main automation entrypoint is [`helmfile.yaml.gotmpl`](helmfile.yaml.gotmpl).
It reads [`versions.yaml`](versions.yaml), installs pinned Helm releases and
uses environment profiles from [`environments/`](environments).

The default environment enables:

- Envoy Gateway, cert-manager and Argo CD.
- CloudNativePG operator and the Barman Cloud backup plugin.
- Strimzi operator and RabbitMQ operators.
- Kafka and Kafka Connect.
- kube-prometheus-stack, Loki, Tempo, Grafana, Alloy and Reloader, plus
  curated Grafana dashboards and PrometheusRules for Kafka, CloudNativePG,
  Loki and cert-manager.
- Valkey, for cluster-internal caching and Redis-compatible dependencies such
  as Infisical.

The optional `all-components` environment also enables ZITADEL and Infisical.
Do not run that environment until their database, master key and application
secrets are created.

The base installation also applies:

- [`resources/kafka/kafka-cluster.yaml`](resources/kafka/kafka-cluster.yaml)
- [`resources/kafka/kafka-connect.yaml`](resources/kafka/kafka-connect.yaml)

Additional stateful resources are available, but are not automatic defaults:

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

# helmfile apply diffs releases through the helm-diff plugin
# (helm 4 verifies plugin signatures by default; git sources need --verify=false):
helm plugin install https://github.com/databus23/helm-diff --verify=false
```

Cluster requirements:

- Kubernetes `v1.30+`.
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
kubectl apply --server-side \
  -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.92.0/stripped-down-crds.yaml
```

The Gateway API CRDs are NOT installed here: they ship with the Envoy Gateway
chart (experimental channel) and upgrade in lockstep with it.

## 4. Install Envoy Gateway, Then cert-manager

Envoy Gateway comes first because it owns the Gateway API CRDs, which
cert-manager's Gateway integration requires at startup. cert-manager comes
before the RabbitMQ topology operator, which uses its webhook certificates.

```sh
helmfile -e default apply --selector profile=edge
helmfile -e default apply --selector profile=certificates

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
kubectl apply --server-side \
  -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.21.1/cluster-operator.yml

kubectl apply --server-side \
  -f https://github.com/rabbitmq/messaging-topology-operator/releases/download/v1.19.3/messaging-topology-operator-with-certmanager.yaml

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

The public URL and the issuer endpoints in `values/grafana.yaml` are
placeholders. Put the real ones in `values/local/grafana.yaml`, a gitignored
file that helmfile layers on top of the committed values when it exists (same
rule as `.local/`: instance-specific names never reach Git):

```yaml
# kubernetes/production-base/values/local/grafana.yaml
grafana.ini:
  server:
    root_url: https://grafana.example.com
  auth.generic_oauth:
    name: ZITADEL
    scopes: openid profile email urn:zitadel:iam:org:id:<org-id>
    auth_url: https://<issuer>/oauth/v2/authorize
    token_url: https://<issuer>/oauth/v2/token
    api_url: https://<issuer>/oidc/v1/userinfo
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

## 7. Install The Default Foundation

When using the repository automation, this step is handled by:

```sh
mise run k8s:base:apply -- --yes
```

For a manual installation from this directory:

```sh
helmfile -e default apply

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

Install the base Kafka and Kafka Connect services:

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

ACME HTTP-01 cannot issue wildcard certificates. Keep one listener per
hostname, or configure a
[DNS-01 solver](https://cert-manager.io/docs/configuration/acme/dns01/) for
your DNS provider before switching to a single `*.your-domain` listener.

## 8. Apply Stateful Resources

Review every resource before applying it. Storage size, backup bucket, endpoint,
replica count and resource requests must match your environment.

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

ZITADEL is disabled by default. It needs PostgreSQL and a 32-byte master key.

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

Edit [`values/zitadel.yaml`](values/zitadel.yaml) and replace
`auth.example.com` with your real domain, then enable the profile:

```sh
helmfile -e all-components apply --selector profile=identity
```

## 10. Optional Infisical

Infisical is disabled by default. It uses a CloudNativePG database and the
base Valkey service instead of the chart's hidden single-node Postgres and
Redis subcharts.

Create a database:

```sh
kubectl apply -f resources/infisical/postgres.yaml
kubectl -n secrets get clusters.postgresql.cnpg.io
```

Create the application secret. The exact keys should match the Infisical
self-hosting configuration you choose:

```sh
kubectl -n secrets create secret generic infisical-secrets \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -hex 16)" \
  --from-literal=AUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=JWT_SIGNUP_SECRET="$(openssl rand -base64 32)" \
  --from-literal=JWT_REFRESH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=JWT_AUTH_SECRET="$(openssl rand -base64 32)" \
  --from-literal=REDIS_URL="redis://valkey.cache.svc.cluster.local:6379" \
  --from-literal=SITE_URL="https://infisical.example.com"

kubectl -n secrets create secret generic infisical-postgres \
  --from-literal=connectionString="postgresql://infisical:<password>@infisical-postgres-rw.secrets.svc.cluster.local:5432/infisical"
```

Edit [`values/infisical.yaml`](values/infisical.yaml) for your domain
configuration, then enable the profile:

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
- Enable SSO/MFA for Argo CD, Grafana, ZITADEL and Infisical.
- Test physical backup restore and logical dump restore.
- Define upgrade windows for Kubernetes, operators and charts.
- Pin application manifests in Git and let Argo CD reconcile them after the
  initial bootstrap.

## Official References

- Gateway API: <https://gateway-api.sigs.k8s.io/guides/>
- Envoy Gateway Helm install: <https://gateway.envoyproxy.io/docs/install/install-helm/>
- cert-manager Helm install: <https://cert-manager.io/docs/installation/helm/>
- Argo CD Helm chart: <https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd>
- CloudNativePG installation and backup: <https://cloudnative-pg.io/documentation/current/>
- RabbitMQ Cluster Operator: <https://www.rabbitmq.com/kubernetes/operator/operator-overview>
- Strimzi documentation: <https://strimzi.io/documentation/>
- Debezium documentation: <https://debezium.io/documentation/>
- ZITADEL Kubernetes deployment: <https://zitadel.com/docs/self-hosting/deploy/kubernetes>
- Infisical Kubernetes deployment: <https://infisical.com/docs/self-hosting/deployment-options/kubernetes>
- kube-prometheus-stack: <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
- Grafana Helm charts: <https://github.com/grafana-community/helm-charts>
- Kubernetes dashboards (dotdc): <https://github.com/dotdc/grafana-dashboards-kubernetes>
- CNPG Barman Cloud plugin: <https://cloudnative-pg.io/plugin-barman-cloud/>
- Valkey Helm chart: <https://github.com/valkey-io/valkey-helm>
- Kubernetes Pod Security Standards: <https://kubernetes.io/docs/concepts/security/pod-security-standards/>
