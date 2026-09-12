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
