# Implementation decisions

This reference records the reasoning that affects safe operation of the source
files. Configuration files and scripts are intentionally comment-free so their
structure, names and validation rules remain the executable explanation. Keep
operational guidance here instead of embedding it beside implementation data.

The only source-comment exceptions are interpreter directives, generated-file
notices, static-analysis source directives and dependency-update directives
required by automation. CI enforces that boundary.

## Deployment engine

The installer separates fresh, legacy and state-managed targets before changing
the cluster. A fresh installation receives the current defaults; a legacy
installation keeps compatible behavior until the operator selects a documented
migration. The installation checkpoint is the source of truth after the first
managed apply. The full state model is in [Compatibility](compatibility.md).

The base Gateway and GatewayClass are bootstrap resources. They are created
only when absent because a real instance adds HTTPS listeners and binds an
EnvoyProxy containing provider load-balancer settings. Reapplying the bootstrap
objects over those changes can replace the load balancer, change its public IP
and break DNS. `OCF_FORCE_BASE_GATEWAY=true` is an explicit recovery override;
restore the instance customization immediately afterward.

The install order is part of the contract:

1. Prometheus Operator CRDs are applied before charts that create
   ServiceMonitors.
2. Envoy Gateway installs and owns the Gateway API CRDs.
3. cert-manager starts after those CRDs and before operators that use its
   webhook certificates.
4. Remaining releases install with bounded concurrency so operator probes are
   not starved on a small fresh cluster.

Every static manifest and custom resource is checked against an upstream CRD
schema. The validation deliberately does not ignore missing schemas. The E2E
suite uses a private temporary kubeconfig and never reads or changes an
operator's normal Kubernetes context. On failure it captures unready Pod logs
and events before deleting the disposable Kind cluster.

Private cluster values belong in the ignored `values/local/<release>.yaml`
layer. Helmfile applies that layer when present for Argo CD, Prometheus, Loki,
Tempo, Alloy, Grafana, ZITADEL and Infisical. Real Terraform inputs, generated
backend files, kubeconfigs and credentials likewise stay under ignored local
paths; committed example files contain placeholders only.

## OCI ownership boundaries

The hardened OCI entrypoint creates a private OKE API endpoint and a managed
Bastion path by default. A public endpoint remains a compatibility option. The
bastion allowlist inherits the API allowlist unless a dedicated list is set.
See [OCI hardening](oci-hardening.md) for migration and access procedures.

OKE requires worker and Pod paths to the API endpoint on TCP 6443 and 12250,
plus ICMP path discovery from workers. Removing those rules prevents kubelets
from registering. A source-preserving OCI Network Load Balancer sends the
original client address to the Envoy NodePort, so the node NSG admits the
declared client CIDRs on the NodePort range. Nodes remain private and have no
direct Internet address.

Terraform and the OCI cloud controller manager share two security-list fields:

- The controller adds public load-balancer-subnet egress rules for Service
  NodePorts. Terraform ignores that egress field but continues to own ingress.
- The controller adds node-subnet ingress rules for each NodePort. Terraform
  ignores that ingress field but continues to own egress.

Without these lifecycle boundaries, a later Terraform apply can briefly remove
the controller's rules and cut traffic to a healthy gateway. Setting
`loadBalancerSourceRanges` can still produce a visible ingress plan difference;
review it instead of accepting silent drift. Changing the OCI load-balancer
type on a live Service replaces the address, so apply the EnvoyProxy NLB
binding before directing production DNS to it.

OKE node-pool taints must be registered by kubelet at startup so scaled or
cycled nodes are safe before ordinary workloads schedule. The generated
cloud-init downloads and invokes OCI's `oke-init.sh` before passing the taints.
The reserved `node-role.kubernetes.io` label prefix cannot be supplied through
kubelet self-labeling; the node-pool helper adds the role label through the
Kubernetes API after nodes join.

## Profiles and defaults

The `starter` profile installs the edge, certificates, GitOps and complete
observability plane. Database and messaging operators are opt-in through
`production`; stateful Kafka, Kafka Connect and Valkey operands are opt-in
through `production-data`. RabbitMQ operators remain disabled in ordinary
profiles because they consume resources without value until a RabbitmqCluster
exists. `all-components` enables every optional product only after its external
secrets and databases are prepared.

CI overlays reduce replicas and retention while keeping production behavior:
Argo CD uses one Redis instance, monitoring uses short retention, Grafana uses
its built-in administrator because no external identity client exists, and
Metrics Server accepts Kind's self-signed kubelet certificate. The Kind cluster
uses three workers so the aggregate requests fit and scheduling still exercises
a multi-node topology.

Metrics Server has explicit requests and tolerant startup, readiness and
liveness probes. The chart's one-second default can restart it during node
contention. The project installs this Helm release rather than the OKE managed
add-on because the current add-on dependency would introduce a second
cert-manager owner.

## Stateful workload sizing

Resource values are safe starting points, not an autosizer. Capacity must be
validated using [Capacity and cost planning](capacity-planning.md).

Strimzi runs cluster-wide so application namespaces can own KafkaConnect and
KafkaConnector resources, while KafkaTopic reconciliation remains scoped to
the Kafka cluster namespace. CPU limits are explicitly removed from the
operator to avoid JVM CFS throttling. Kafka controller and broker memory limits
bound the derived heap; requests prevent the scheduler from stacking replicas
on one node. Pod anti-affinity is essential because replication factor three
does not protect replicas that share a failed node.

The example broker volume is 400 GiB. It was sized from a large Debezium
migration rather than presented as a universal default: CDC topics with
unbounded retention will eventually fill any disk. Set a retention policy from
the recovery objective and measure encoded topic growth before production use.
Kafka Connect's 450 MiB observed baseline excludes heavy connectors.

CloudNativePG physical backups and WAL archives use the Barman Cloud plugin;
the older in-tree object-store integration is deprecated. OCI Object Storage
uses its S3 compatibility endpoint and a Customer Secret Key. A restore must
use the `serverName` of the cluster that produced the backup. Logical backup
and restore procedures live beside the examples in
[`logical-dump-restore.md`](../kubernetes/production-base/resources/cnpg/logical-dump-restore.md).

Valkey runs under the restricted Pod Security Standard, including its exporter
sidecar, and uses ACL authentication plus retained persistence for fresh
installations. Grafana uses `Recreate` because its default data volume is
ReadWriteOnce; the first migration from a live RollingUpdate deployment may
need the client-side Helm procedure documented in [Lifecycle](lifecycle.md).

Loki retains 14 days and runs at warning log level to avoid storing its own
per-query and per-flush noise. Persistent-volume storage is a small-cluster
default only. Before high-volume use, move Loki and Tempo to object storage.
For an existing Loki installation, add a new schema period starting on a future
date; never edit the active schema period in place.

## Observability behavior

The blackbox exporter has three intentional probe semantics:

- `http_2xx` represents a public page that must return success.
- `http_reachable` accepts redirects, authentication responses and missing
  root routes while rejecting server errors.
- `tls_connect` checks certificate expiry for non-HTTP listeners.

Probe resources supply targets, so the chart's own ServiceMonitor is disabled
to avoid duplicate series. Envoy proxy metrics use a stable Prometheus job name
because alert rules must not depend on the generated namespace/PodMonitor job
name. Route alert thresholds are initial values and should be calibrated from
at least one representative week before they page an operator.

Tempo generates service-graph and span metrics into Prometheus. Prometheus
stores exemplars so Grafana can move from a latency sample to its trace. Alloy
parsing is opt-in with `logging.open-cluster-foundation.io/format=java|json`:
Java parsing joins stack traces and JSON parsing promotes level, trace and span
fields. Unannotated logs remain unchanged to prevent unrelated multiline
formats from being merged incorrectly.

Grafana datasource UIDs are fixed because changing a provisioned UID can stop
Grafana from starting. Its datasource links cover exemplars, structured trace
metadata and ECS-formatted log lines. Alertmanager credentials are mounted from
a Secret; the example routes application namespaces separately from platform
alerts and sends Watchdog and InfoInhibitor to the null receiver.

## TLS and external endpoints

The supplied cert-manager issuers use ACME HTTP-01, which requires concrete
hostnames and cannot issue wildcard certificates. Use a DNS-01 solver for a
wildcard listener. Start with the Let's Encrypt staging issuer and change to
production only after successful issuance. The catch-all HTTP redirect does
not mask the more-specific challenge route created by cert-manager.

OCI S3-compatible examples require the tenancy Object Storage namespace,
bucket names and Customer Secret Keys supplied outside Git. Workload and
instance principals are not accepted by that compatibility API. The example
files must be copied and adapted; they are never complete production inputs.

## Third-party configuration provenance

The following configuration is adapted under Apache License 2.0 terms:

- Kafka JMX exporter rules, Kafka PodMonitors and Kafka PrometheusRules from
  [Strimzi Kafka Operator](https://github.com/strimzi/strimzi-kafka-operator),
  version 1.0.1 examples. OCF extends Pod-name expressions for KafkaNodePools
  and omits `NoMessageForTooLong`, which is permanently noisy on low-traffic
  Kafka Connect internal topics.
- CloudNativePG PrometheusRules from
  [CloudNativePG](https://github.com/cloudnative-pg/cloudnative-pg), version
  1.29.1 samples, with OCF metadata.

The cert-manager alerts are curated from the
[cert-manager mixin](https://monitoring.mixins.dev/cert-manager/). The Tempo,
edge and platform rules and dashboards are authored for OCF. Community Grafana
dashboards are fetched by pinned dashboard ID and revision listed in the
Grafana values.
