# Installation and Upgrade Compatibility

Open Cluster Foundation classifies every target before an apply. The
classification makes first installation and upgrade behavior explicit without
silently changing an existing cluster's profile.

| Detected state | Meaning | Automatic mode |
| --- | --- | --- |
| `fresh` | No OCF state or known base workload exists. | Fresh installation |
| `legacy` | Known OCF workloads exist but no state ConfigMap exists. | Compatible upgrade and adoption |
| `managed` | The OCF state ConfigMap exists with a supported schema. | Managed upgrade |
| `partial` | An apply checkpoint exists because an operation has not completed. | Resume the recorded operation exactly |

`--mode auto` is the default and selects the operation from the detected state.
Use `--mode fresh` or `--mode upgrade` in automation when a mismatch must stop
the deployment. A fresh operation refuses a cluster with known OCF workloads,
and an upgrade refuses an empty cluster.

When no environment is specified, a fresh cluster selects `starter`, a legacy
cluster selects the compatibility-only `default`, and a managed cluster reuses
the environment recorded by its last successful apply. This keeps stateful
application services out of new installations while preserving existing Kafka,
Kafka Connect and Valkey installations during upgrades.

Immediately before changing components, OCF writes
`platform-system/open-cluster-foundation-operation` with the selected
environment, mode and migration controls. If the process fails or is
interrupted, the next `check` or `apply` detects that checkpoint and reuses the
recorded settings. A conflicting environment or migration option is rejected
until the idempotent apply completes. This prevents an interrupted fresh
installation from being mistaken for a legacy installation with a broader
default profile.

After every successful apply, OCF writes
`platform-system/open-cluster-foundation-installation`. The ConfigMap records
the state schema, environment, resolved operation, installation origin, source
revision, component-version digest, enabled profiles, NetworkPolicy state,
observability scope, identity access mode, cache access mode and completion
time. OCF then removes the operation checkpoint. A failed or interrupted apply
does not replace the last successful state; its operation checkpoint remains
as the safe resume contract.

The first successful apply to a legacy installation records `origin=adopted`.
It does not change the selected environment or enable new components merely
because state metadata was absent.

Changing the Helmfile environment on a managed installation is rejected by
default because it can install or remove whole component profiles. Review the
profile difference and pass `--allow-environment-change` explicitly when that
transition is intended.

The compatibility rules are:

- `check` and `render` never write to a cluster.
- Existing resources continue through the upgrade path unless an explicit
  migration gate is accepted.
- New secure defaults may apply automatically to fresh installations; an
  existing installation keeps its prior behavior until its documented
  migration is selected.
- Installation state describes the last completed apply. It is not a backup or
  rollback mechanism.

## Gateway route attachment migration

Fresh installations allow HTTPRoutes to attach to the public Gateway only from
namespaces labeled `open-cluster-foundation.io/gateway-access=public`. OCF
labels the platform, Argo CD, monitoring and identity namespaces because those
profiles can expose public routes.

Upgrades do not rewrite an existing Gateway. A legacy Gateway that uses
`allowedRoutes.namespaces.from: All` remains unchanged until its operator
migrates the private instance manifest. This prevents an upgrade from detaching
working application routes.

Audit the current routes with an explicit context:

```sh
mise run k8s:gateway:check-access -- --context <context>
```

The check is read-only and fails with every attached route namespace that lacks
the access label. Label only namespaces whose users are trusted to publish a
route through the shared public Gateway:

```sh
kubectl --context <context> label namespace <namespace> \
  open-cluster-foundation.io/gateway-access=public
```

Run the check again. Only after it passes, change every listener in the private
Gateway manifest to:

```yaml
allowedRoutes:
  namespaces:
    from: Selector
    selector:
      matchLabels:
        open-cluster-foundation.io/gateway-access: public
```

Apply the private Gateway manifest, verify that all expected HTTPRoutes still
have `Accepted=True`, and test each public hostname. To roll back, restore
`from: All` in the same private manifest and apply it again.

## NetworkPolicy migration

Fresh installations enforce the OCF NetworkPolicy chart after every selected
component is ready. The installation state records
`network-policies=enforced`, so later automatic upgrades continue reconciling
the same policies.

Legacy installations and managed installations without that state remain in
`preserve` mode. They receive namespace labels but no NetworkPolicy resources,
so adoption cannot interrupt existing traffic. Confirm the selected behavior
with the read-only preflight:

```sh
mise run k8s:base:check -- --network-policies auto
```

Before opting in, inventory every client of PostgreSQL, Kafka, RabbitMQ,
Valkey, ZITADEL, Infisical and the observability ingestion endpoints. Label
application namespaces according to the access they require:

```sh
kubectl --context <context> label namespace <namespace> \
  open-cluster-foundation.io/platform-access=true
kubectl --context <context> label namespace <namespace> \
  open-cluster-foundation.io/observability-access=true
```

`platform-access` permits only the documented service ports. It does not grant
route attachment. `observability-access` permits Prometheus discovery and is
one of the two required controls for telemetry ingestion. Public HTTPRoute
namespaces independently require
`open-cluster-foundation.io/gateway-access=public`.

Test DNS, HTTPS egress, public routes, database connections, messaging and
telemetry from a labeled canary namespace. Then enforce the policies with the
explicit migration option:

```sh
mise run k8s:base:apply -- --mode upgrade --network-policies enforce --yes
```

The policy contract allows communication among OCF-managed namespaces, DNS on
TCP/UDP 53, outbound HTTP/HTTPS, Kubernetes admission webhooks, public Envoy
listeners, the Kubernetes API on TCP 443/6443 and labeled access to platform
services. Other ingress and egress is denied in OCF-managed namespaces.

If a missed dependency causes an outage, remove only the policy release and
restore service before changing the allowlist:

```sh
helm --kube-context <context> -n platform-system uninstall ocf-network-policies
```

An uninstall is a rollback of isolation, not of workloads or data. Re-run the
apply with `--network-policies enforce` after correcting and testing the chart.

## Observability trust migration

Fresh installations use `observability-scope=trusted`. Prometheus discovers
ServiceMonitors, PodMonitors, PrometheusRules, Probes and ScrapeConfigs only in
namespaces labeled `open-cluster-foundation.io/observability-access=true`.
Probes additionally require `open-cluster-foundation.io/probe=trusted`, and
ScrapeConfigs require `open-cluster-foundation.io/scrape-config=trusted`.
Grafana watches dashboard ConfigMaps only in `monitoring` with namespaced RBAC;
the Strimzi dashboards are created there. Alloy reads logs from OCF-managed
namespaces and from explicitly trusted application Pods.

Legacy installations and managed installations without an observability scope
retain `observability-scope=legacy`. This preserves cluster-wide Prometheus,
Grafana and Alloy discovery during adoption. Inspect the current sources before
migrating:

```sh
kubectl --context <context> get servicemonitor,podmonitor,prometheusrule,probe,scrapeconfig -A
kubectl --context <context> get configmap -A -l grafana_dashboard=1
kubectl --context <context> get namespace --show-labels
```

Label every application namespace whose metrics or telemetry are accepted:

```sh
kubectl --context <context> label namespace <namespace> \
  open-cluster-foundation.io/observability-access=true
```

Telemetry clients also need the workload identity on their Pod template:

```yaml
spec:
  template:
    metadata:
      labels:
        open-cluster-foundation.io/telemetry-client: trusted
```

The combined namespace and Pod labels permit log collection and network access
to Loki, Tempo OTLP and the Prometheus remote-write receiver. The namespace
label alone permits metrics discovery but not telemetry ingestion. Move custom
Grafana dashboard ConfigMaps into `monitoring`, and label each custom Probe or
ScrapeConfig with its corresponding trusted resource label.

Run the preflight and apply again whenever a namespace is newly labeled. The
installer resolves the labeled application namespace set into Alloy's discovery
configuration; this prevents Alloy from watching unrelated application Pods.

Test metrics, logs, traces, remote write, probes and dashboards from a canary.
Then enable both required controls in one apply:

```sh
mise run k8s:base:apply -- --mode upgrade --network-policies enforce \
  --observability-scope trusted --yes
```

The installer rejects trusted observability without enforced NetworkPolicies.
To restore discovery while investigating a missed source, keep the policies in
place and run:

```sh
mise run k8s:base:apply -- --mode upgrade --observability-scope legacy --yes
```

Direct Helmfile runs default to the trusted scope because they cannot detect
installation history. Use `OCF_OBSERVABILITY_SCOPE=legacy` only for a reviewed
manual upgrade that intentionally preserves the former discovery behavior.

## Identity access migration

Fresh installations use `identity-access=sso`. Argo CD disables its local
administrator and assigns no default application permission beyond the empty
`role:authenticated`. Grafana disables the login form, enables PKCE and refresh
tokens, requires explicit group-derived roles and prevents OAuth claims from
assigning Grafana server administrator. The CI profile disables external OAuth
because its cluster is disposable and has no identity provider.

Legacy installations and managed installations without an identity access
state retain `identity-access=legacy`. This preserves the Argo CD local
administrator, default read-only Argo CD access and the former Grafana login
and OAuth mapping during adoption. An automatic upgrade therefore does not
lock operators out of an existing cluster.

Create separate OIDC applications for Argo CD and Grafana. While the cluster
is still in legacy mode, configure their exact redirect URIs, require MFA at
the identity provider, create administrator and read-only/viewer groups and
place the application settings in the two gitignored local values files. Start
from `values/local-examples/argocd.yaml` and
`values/local-examples/grafana.yaml`.

Create the credentials without committing them:

```sh
kubectl --context <context> -n argocd create secret generic argocd-oidc-credentials \
  --from-literal=clientSecret='<secret>'
kubectl --context <context> -n argocd label secret argocd-oidc-credentials \
  app.kubernetes.io/part-of=argocd
kubectl --context <context> -n monitoring create secret generic grafana-oidc-credentials \
  --from-literal=client_id='<client-id>' \
  --from-literal=client_secret='<secret>'
```

Run the read-only preflight, then enable SSO explicitly:

```sh
mise run k8s:base:check -- --mode upgrade --identity-access sso
mise run k8s:base:apply -- --mode upgrade --identity-access sso --yes
```

Use a private browser session to verify an administrator login and a
read-only/viewer login in both products. Confirm that an unmapped identity has
no application role. Keep a current cluster-admin kubeconfig outside Argo CD;
it is the recovery path if the identity provider is unavailable.

To restore the former local access while investigating a failed migration:

```sh
mise run k8s:base:apply -- --mode upgrade --identity-access legacy --yes
```

Direct Helmfile runs default to SSO because they cannot detect installation
history. Set `OCF_IDENTITY_ACCESS_MODE=legacy` only for a reviewed manual
upgrade that intentionally preserves the former access model.

## Cache access migration

Fresh installations use `cache-access=acl` whenever their selected profile
enables Valkey. The default ACL password lives only in the existing Secret
`cache/valkey-acl`; values files contain permissions and the Secret reference,
never the credential. Valkey also enables an append-only log with one-second
fsync, retains its PVC after a Helm uninstall and uses `Recreate` because the
standalone volume is ReadWriteOnce.

Legacy installations and managed installations without a cache access state
retain `cache-access=legacy`. They continue accepting unauthenticated clients,
so adoption cannot disconnect a running Kafka connector, application or
Infisical instance.

Inventory every Valkey client and schedule a coordinated cutover. Create the
ACL Secret without placing the password in shell history:

```sh
VALKEY_PASSWORD="$(openssl rand -base64 32)"
kubectl --context <context> -n cache create secret generic valkey-acl \
  --from-literal=default="$VALKEY_PASSWORD"
```

Prepare each client to use username `default` and that password. Infisical
loads them from `REDIS_USERNAME` and `REDIS_PASSWORD` keys in its own Secret;
its `REDIS_URL` remains `redis://valkey.cache.svc.cluster.local:6379`. Use your
secret-delivery system to copy the credential into application namespaces,
then clear the local variable:

```sh
unset VALKEY_PASSWORD
```

During the maintenance window, enable ACL and roll out the prepared clients:

```sh
mise run k8s:base:apply -- --mode upgrade --cache-access acl --yes
```

Verify that unauthenticated `PING` returns `NOAUTH`, authenticated clients can
read and write, and the exporter still exposes metrics. To restore the former
access while fixing a missed client, run:

```sh
mise run k8s:base:apply -- --mode upgrade --cache-access legacy --yes
```

The rollback does not delete the ACL Secret or PVC. Direct Helmfile runs
default to ACL because they cannot detect installation history; set
`OCF_CACHE_ACCESS_MODE=legacy` only for a reviewed manual upgrade.
