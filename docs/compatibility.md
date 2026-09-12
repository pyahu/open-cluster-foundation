# Installation and Upgrade Compatibility

Open Cluster Foundation classifies every target before an apply. The
classification makes first installation and upgrade behavior explicit without
silently changing an existing cluster's profile.

| Detected state | Meaning | Automatic mode |
| --- | --- | --- |
| `fresh` | No OCF state or known base workload exists. | Fresh installation |
| `legacy` | Known OCF workloads exist but no state ConfigMap exists. | Compatible upgrade and adoption |
| `managed` | The OCF state ConfigMap exists with a supported schema. | Managed upgrade |

`--mode auto` is the default and selects the operation from the detected state.
Use `--mode fresh` or `--mode upgrade` in automation when a mismatch must stop
the deployment. A fresh operation refuses a cluster with known OCF workloads,
and an upgrade refuses an empty cluster.

When no environment is specified, a fresh cluster selects `starter`, a legacy
cluster selects the compatibility-only `default`, and a managed cluster reuses
the environment recorded by its last successful apply. This keeps stateful
application services out of new installations while preserving existing Kafka,
Kafka Connect and Valkey installations during upgrades.

After every successful apply, OCF writes
`platform-system/open-cluster-foundation-installation`. The ConfigMap records
the state schema, environment, resolved operation, installation origin, source
revision, component-version digest, enabled profiles and completion time. A
failed or interrupted apply never updates this state.

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
route attachment. `observability-access` permits telemetry ingestion and
Prometheus scraping. Public HTTPRoute namespaces independently require
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
