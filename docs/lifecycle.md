# Upgrade, rollback, uninstall and recovery

Open Cluster Foundation reconciles infrastructure and platform components; it
does not own application data or replace a disaster-recovery plan. Use a
dedicated kubeconfig containing only the target cluster for every mutable
operation. Record the repository revision, Terraform plan, selected Helmfile
environment and OCF installation state with the change ticket.

Never test these procedures first on production. Rehearse them against a
representative non-production cluster and restore real backups on a schedule.

## Evidence before a change

Set a dedicated kubeconfig and verify the target before running OCF:

```sh
export KUBECONFIG=/absolute/path/to/target.kubeconfig
kubectl config current-context
kubectl get --raw=/readyz
kubectl get nodes -o wide
kubectl -n platform-system get configmap \
  open-cluster-foundation-installation \
  open-cluster-foundation-operation \
  --ignore-not-found -o yaml
helm list --all-namespaces
```

A missing installation ConfigMap with existing workloads is a supported
`legacy` adoption state. A present operation ConfigMap is a `partial` state and
must be resumed with its recorded settings. Do not delete either ConfigMap to
bypass a compatibility check.

Before infrastructure changes, archive the current Terraform state outside the
state bucket and confirm OCI Object Storage versioning is enabled. Before
Kubernetes changes, preserve private values, the list of releases and exported
application manifests. Back up every stateful service with its own supported
mechanism and prove at least one recent restore. The OCF ConfigMaps and Helm
release history are metadata, not data backups.

## Upgrade

1. Select an immutable project release and read its changelog, the generated
   [compatibility reference](reference/compatibility.md) and every applicable
   migration in [installation compatibility](compatibility.md).
2. Install the tool versions from that revision with `mise install`.
3. Run the Terraform plan and save it. An empty or reviewed additive plan is
   required before applying; unexplained replacement of the cluster, VCN,
   subnets, node pools or state bucket stops the upgrade.
4. Run the Kubernetes preflight and render using the environment recorded in
   the installation ConfigMap. Review the Helm diff, removed resources, CRD
   changes, immutable fields and storage changes.
5. Apply Terraform first when the Kubernetes layer depends on new cloud
   capacity or networking. Apply the Kubernetes base second. Pass migration
   gates only after their specific canary and rollback procedure has been
   tested.
6. Verify node readiness, all rollouts, Gateway and HTTPRoute conditions,
   certificate issuance, metrics, logs, traces and application-specific smoke
   tests. Confirm the operation checkpoint is gone and the successful
   installation state records the expected source revision.

Typical read-only and apply commands are:

```sh
ENVIRONMENT=production
NETWORK_POLICY_MODE=enforce
OBSERVABILITY_SCOPE=trusted
IDENTITY_ACCESS_MODE=sso
CACHE_ACCESS_MODE=acl

mise run oci:cluster:plan
mise run k8s:base:check -- --environment "$ENVIRONMENT" --mode upgrade
mise run k8s:base:render -- --environment "$ENVIRONMENT" \
  --network-policies "$NETWORK_POLICY_MODE" \
  --observability-scope "$OBSERVABILITY_SCOPE" \
  --identity-access "$IDENTITY_ACCESS_MODE" \
  --cache-access "$CACHE_ACCESS_MODE"
(cd kubernetes/production-base && \
  OCF_OBSERVABILITY_SCOPE="$OBSERVABILITY_SCOPE" \
  OCF_IDENTITY_ACCESS_MODE="$IDENTITY_ACCESS_MODE" \
  OCF_CACHE_ACCESS_MODE="$CACHE_ACCESS_MODE" \
  helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" diff)
mise run oci:cluster:apply -- --yes
mise run k8s:base:apply -- --environment "$ENVIRONMENT" --mode upgrade --yes
```

The OCI apply task regenerates and displays its plan before confirmation. Use
the exact plan/apply argument syntax supported by the selected release. Never
reuse a saved Terraform plan after variables, provider credentials, state, or
the selected revision changes. Render does not query installation history, so
pass the controls recorded in the installation ConfigMap to preview an upgrade
faithfully. Translate the recorded NetworkPolicy state `enforced` to the CLI
mode `enforce`; use `preserve` for every other recorded state. Replace all five
example variable values before running the commands.

## Failed or interrupted apply

Helm releases use atomic upgrades and cleanup-on-failure, but cluster-scoped
CRDs, pre-applied manifests and external data services are not fully rolled
back by Helm. Capture events and failing workload logs before retrying.

When `open-cluster-foundation-operation` exists, re-run the same revision with
the same environment, mode and migration controls. The installer rejects a
conflicting request and keeps the last completed installation state unchanged.
After the retry succeeds, verify that the checkpoint was removed.

If the recorded revision cannot be recovered, stop automated applies. Export
both state ConfigMaps, reconstruct that revision and its private values, or
perform a reviewed manual recovery. Deleting the checkpoint can cause a
partial installation to be misclassified and is not a recovery procedure.

## Kubernetes rollback

Prefer a forward fix when a new CRD, persistent-volume format, database schema
or operator-managed resource has changed. A source rollback is appropriate
only when the prior release documents compatibility with the live CRDs and
data formats.

For a compatible rollback, check out the prior immutable release, restore its
private values, run `check` and `render`, review the reverse Helm diff, then
apply in upgrade mode with the environment already recorded in the cluster.
Do not use `helm rollback` independently for a release managed by Helmfile;
that creates drift which the next OCF apply will overwrite.

Migration-specific rollback commands live in
[installation compatibility](compatibility.md). Restore application data from
backup when validation shows corruption; reverting manifests does not revert
stored data.

## Terraform rollback and state recovery

Terraform has no general rollback command. Never restore an older state object
while newer infrastructure still exists: the next plan may attempt duplicate
creation or destructive replacement. Correct configuration forward whenever
possible.

If state is lost or corrupt, suspend applies, make an independent copy of the
current and prior Object Storage object versions, identify the last valid
state and compare it with live OCI resources. Restore or import resources only
through a peer-reviewed recovery plan. Always run `terraform plan` afterward;
any unexplained create, destroy or replacement means recovery is incomplete.

## Uninstall

There is intentionally no one-command uninstall. Removing operators before
their custom resources, finalizers and backups are handled can orphan cloud
resources or make data recovery impossible. Terraform destruction can remove
the entire cluster and network.

Use this order in a maintenance window:

1. Disable GitOps reconciliation and new writes, then inventory OCF Helm
   releases, custom resources, persistent volumes, load balancers and OCI
   resources.
2. Produce and restore-test final backups. Record PVC reclaim policies and the
   external object-storage paths that must be retained.
3. Remove application custom resources deliberately, one product at a time,
   following its upstream deletion and finalizer procedure. Confirm external
   resources and retained volumes after each product.
4. Destroy only the reviewed Helmfile environment from the same release and
   private values used to install it. Manually review cluster-scoped CRDs and
   installer-applied manifests; Helmfile does not own all of them.
5. Delete OCF namespaces only after they are empty and every retained object is
   accounted for. Remove the OCF state ConfigMaps last.
6. Run and approve a Terraform destroy plan only when the OKE cluster, network
   and their remaining cloud resources are intended to be permanently removed.
   Keep the remote state bucket and independent backups until retention policy
   permits deletion.

Never use uninstall as rollback. If the goal is to restore service, use the
failed-apply or rollback procedures above.

After steps 1 through 3 are complete and independently reviewed, the Helmfile
portion is removed with:

```sh
ENVIRONMENT=production
cd kubernetes/production-base
helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" list
helmfile -f helmfile.yaml.gotmpl -e "$ENVIRONMENT" destroy
```

This does not remove the separately managed `ocf-network-policies` release,
upstream manifest installations, monitoring resources, Gateway resources,
namespaces, application custom resources or persistent volumes. Inventory and
remove each of those explicitly; do not assume the Helmfile command completed
the uninstall.

## Disaster recovery

Recovery order is dependency-driven: OCI network and OKE, cluster access,
operators, object-store credentials, stateful data, then stateless workloads
and routes. Generate a fresh kubeconfig from Terraform output rather than
restoring an expired local token. Reapply the same OCF release and environment
that produced the backup before restoring application data.

For CloudNativePG, use the physical backup/PITR resources and the independent
[logical dump procedure](../kubernetes/production-base/resources/cnpg/logical-dump-restore.md).
Kafka, RabbitMQ, Valkey, ZITADEL, Infisical, Grafana and observability object
stores require product-specific backups and tested recovery objectives; OCF
does not create a universal backup for them.

Complete recovery only after data integrity checks, external DNS and TLS
validation, application smoke tests, monitoring ingestion and a new backup all
succeed.
