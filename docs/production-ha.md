# Production HA profile

`production-ha` is the failure-tolerant OCF profile. It is opt-in and does not
change `starter`, `production`, `production-data`, `default`, `all-components`
or `ci`. Existing installations therefore keep their current topology until an
operator explicitly changes the managed environment.

The profile runs three replicas of user-facing and reconciliation services,
uses hard anti-affinity between hosts and best-effort spread between zones and
adds disruption budgets that preserve quorum or two serving replicas. It also
changes the observability data path:

| Signal | Durable path | Local working storage | Default retention |
| --- | --- | --- | --- |
| Metrics | Prometheus replicas upload blocks to S3-compatible storage; Thanos Query reads replicas and Thanos Store; Thanos Compactor applies retention | 2 × 100 GiB Prometheus, 3 × 20 GiB Store cache, 1 × 50 GiB compactor | 15 days locally; 30 days raw, 180 days at 5 minutes and 365 days at 1 hour in Thanos |
| Logs | Three Loki monolithic replicas use a shared S3-compatible object store | 3 × 20 GiB | 30 days |
| Traces | Distributed Tempo uses three distributors, ingesters, queriers, query frontends and metrics generators with a shared S3-compatible object store | 3 × 20 GiB ingester WAL and 3 × 10 GiB metrics-generator WAL | 30 days |
| Dashboards | Three Grafana replicas share an external highly available PostgreSQL database | None | Defined by the database backup policy |

The supported durable backend in this profile is the S3 API. That covers AWS
S3 and compatible services such as OCI Object Storage's S3 compatibility API.
Native GCS and Azure Blob configurations require additional provider-specific
values and preflight support and are not claimed by this profile.

## Prerequisites

- At least three Ready, schedulable nodes without general `NoSchedule` or
  `NoExecute` taints.
- Every eligible node labeled with `topology.kubernetes.io/zone` and at least
  two distinct zone values.
- A default `ReadWriteOnce` StorageClass.
- An S3-compatible endpoint using TLS, separate Loki, Tempo and Thanos buckets,
  bucket versioning, server-side encryption and lifecycle rules.
- A PostgreSQL service that remains writable after one database instance or
  zone fails. Its backups must be independent from the cluster.
- The private CIDR or CIDRs resolved by the PostgreSQL hostname. They are the
  only external destinations granted to Grafana on TCP 5432.
- The capacity and cost review in [capacity planning](capacity-planning.md).

The topology check runs before confirmation and before any cluster mutation.
`render` remains offline and can render placeholders for review; `check` and
`apply` reject missing production values and Secrets.

## Configure values

From `kubernetes/production-base`:

```sh
mkdir -p values/local
cp values/local-examples/argocd.yaml values/local/argocd.yaml
cp values/local-examples/grafana.yaml values/local/grafana.yaml
cp values/local-examples/loki.yaml values/local/loki.yaml
cp values/local-examples/tempo-distributed.yaml values/local/tempo-distributed.yaml
${EDITOR:-vi} values/local/argocd.yaml values/local/grafana.yaml \
  values/local/loki.yaml values/local/tempo-distributed.yaml
```

Use three different Loki buckets and separate buckets for Tempo and Thanos.
Do not reuse a bucket across components because their retention and object
layouts are unrelated.

## Create inputs

Create namespaces first. The literal commands below describe the required
Secret contract; in an operated environment, materialize the same keys from
your secret manager instead of retaining credentials in shell history.

```sh
kubectl apply -f manifests/namespace-baseline.yaml

kubectl -n monitoring create secret generic observability-object-storage \
  --from-literal=LOKI_S3_ENDPOINT='https://object-storage.example.com' \
  --from-literal=TEMPO_S3_ENDPOINT='object-storage.example.com' \
  --from-literal=S3_REGION='replace-me' \
  --from-literal=AWS_ACCESS_KEY_ID='replace-me' \
  --from-literal=AWS_SECRET_ACCESS_KEY='replace-me' \
  --from-literal=TEMPO_S3_BUCKET='replace-me-tempo'

kubectl -n monitoring create secret generic grafana-database \
  --from-literal=GF_DATABASE_HOST='postgres.example.internal:5432' \
  --from-literal=GF_DATABASE_NAME='grafana' \
  --from-literal=GF_DATABASE_USER='grafana' \
  --from-literal=GF_DATABASE_PASSWORD='replace-me' \
  --from-literal=GF_SECURITY_SECRET_KEY="$(openssl rand -hex 32)"
kubectl -n monitoring create secret generic grafana-database-ca \
  --from-file=ca.crt=/private/path/postgresql-ca.crt
```

Place the Thanos object-store configuration in a file that is never committed:

```yaml
type: S3
config:
  bucket: replace-me-thanos
  endpoint: object-storage.example.com
  region: replace-me
  access_key: replace-me
  secret_key: replace-me
  insecure: false
```

Create its Secret:

```sh
kubectl -n monitoring create secret generic thanos-object-storage \
  --from-file=objstore.yml=/private/path/thanos-objstore.yml
```

Cloud workload identity is supported for Thanos by setting
`config.aws_sdk_auth: true` and omitting static access keys. Loki and Tempo in
the current S3 profile consume the credential environment variables above.

## Validate and install

Use an explicit context for every inspection. Confirm the environment change
only after reviewing the Helm diff and a backup/restore exercise:

```sh
kubectl --context <context> get nodes \
  -L topology.kubernetes.io/zone
OCF_K8S_ENVIRONMENT=production-ha \
  OCF_GRAFANA_DATABASE_CIDRS='10.20.30.40/32' \
  scripts/k8s-production-base.sh check --mode upgrade
OCF_GRAFANA_DATABASE_CIDRS='10.20.30.40/32' \
  scripts/k8s-production-base.sh render --environment production-ha
OCF_GRAFANA_DATABASE_CIDRS='10.20.30.40/32' \
  scripts/k8s-production-base.sh apply --environment production-ha \
  --mode upgrade --allow-environment-change --yes
```

After installation, verify that all replicas are Ready, PodDisruptionBudgets
allow one disruption, Prometheus sees both sidecars through Thanos Query and
new Loki and Tempo data remains queryable after deleting one pod. A change to
`production-ha` is not complete until Grafana database restore and each object
store's recovery procedure have also been tested.
