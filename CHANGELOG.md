# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); releases use calver
tags (`vYYYY.M.PATCH`).

## [Unreleased]

## [2026.9.0] - 2026-09-13

### Added

- A maintained implementation-decisions reference for safety-sensitive
  defaults, ownership boundaries, sizing assumptions and third-party
  configuration provenance.
- Generated component, Kubernetes, provider and environment compatibility
  references, with CI checks that reject stale output, invalid compatibility
  metadata and broken local Markdown links.
- A lifecycle runbook covering evidence collection, safe upgrades, partial
  operation recovery, rollback limits, ordered uninstall and disaster recovery.
- A GitHub question form for usage and operational support.
- Edge monitoring: PodMonitor for every Envoy proxy and ServiceMonitor for the
  Envoy Gateway controller, recording rules for request rate and p95 latency
  per HTTPRoute (`namespace`/`route` labels), and alerts for route error rate,
  route latency and proxy or controller down. Envoy Gateway overview
  dashboard in a new "Platform" Grafana folder.
- Synthetic probes: blackbox exporter release with `http_2xx`,
  `http_reachable` and `tls_connect` modules, an example Probe, alerts for
  failing, slow and certificate-expiring endpoints, and the blackbox HTTP
  dashboard. Prometheus now selects Probe and ScrapeConfig resources from
  any namespace, like the other monitoring resources.
- Correlated observability: Tempo metrics generator (span metrics and service
  graph) writing to Prometheus through the remote-write receiver, exemplar
  storage, and Grafana datasource links between logs, traces and metrics.
- Opt-in log parsing in Alloy through the
  `logging.open-cluster-foundation.io/format` pod annotation (`java`: multiline
  stack traces and a `level` label; `json`: `level` label and trace/span ids as
  structured metadata).
- Tempo alerts (down, discarding spans), an Alertmanager datasource in
  Grafana, and Capacity and Alerts dashboards in the Platform folder (dashboard
  ConfigMaps choose their folder with the `grafana_folder` annotation).
- `values/local-examples/kube-prometheus-stack.yaml`: routing application
  namespaces and platform alerts to separate receivers, with credentials read
  from a mounted Secret.
- Platform dashboards: a home Platform overview (alerts, targets, probes, node
  memory, routes, CDC and consumer lag, queues, databases, caches, error logs),
  CDC / Debezium by namespace, a Logs explorer, and Traces with the Tempo
  service map. Community dashboards pinned by revision for RabbitMQ, the Redis
  exporter (Valkey), cert-manager and Argo CD.
- `values/local/<release>.yaml` instance layer for kube-prometheus-stack,
  Loki, Tempo and Alloy, as Grafana already had.

### Changed

- Operational explanations now live in documentation instead of source
  comments; CI rejects comments other than required interpreter, generated-file,
  static-analysis and dependency-update directives.
- The end-to-end cluster now pins its Kind node image by digest and asserts the
  documented Kubernetes server version before installation.
- Component and support claims now come from generated references instead of
  manually copied README tables; the unavailable Discussions link was removed.
- Fresh installations now use group-mapped SSO-only access for Argo CD and
  Grafana, with Argo CD local admin disabled, no implicit application access,
  Grafana PKCE and refresh tokens, strict roles and no OAuth server-admin
  assignment. Existing installations retain the former access model behind an
  explicit, stateful migration gate.
- Fresh Valkey installations now require an external ACL Secret, enable
  append-only persistence, retain their PVC and use a ReadWriteOnce-safe update
  strategy. Legacy clusters retain unauthenticated access behind an explicit
  cache migration gate.
- ZITADEL and Infisical now have validated private instance layers, bounded
  resources, replica spreading, PodDisruptionBudgets, restricted runtime
  security and working Gateway API routes. Their required cryptographic keys,
  database TLS and cache credentials are validated before installation.
- The blackbox `http_reachable` module accepts 404 and 405: an API with
  nothing mapped at `/` answers that way and is up. The module now matches its
  own description, anything but a server error.

- Grafana deploys with the `Recreate` strategy: its data volume is
  ReadWriteOnce, and a rolling update left the new pod waiting for the volume
  until an atomic upgrade timed out and rolled back. On an existing release,
  run the first upgrade after this change with `--server-side=false`: Helm 4's
  server-side apply keeps the live `rollingUpdate` block and the API refuses
  it next to `Recreate`.
- Loki and Alloy log at `warn`. At `info` they logged a line per query and per
  flushed stream, which in a quiet cluster was most of what Loki stored.

- OCI foundation: remote state bootstrap, VCN with IGW/NAT (reserved public
  IP)/Service Gateway, ENHANCED OKE cluster with VCN-native pod networking,
  per-layer NSGs, node pools with kubelet-registered labels and taints,
  managed Metrics Server addon, optional managed Bastion for private API
  endpoints, and a private-instance template workflow.
- Layer-4 ingress on OCI through a source-IP-preserving Network Load
  Balancer, wired to Envoy Gateway via an EnvoyProxy resource.
- Kubernetes production base via Helmfile: Envoy Gateway (Gateway API),
  cert-manager with Let's Encrypt issuers, Argo CD, CloudNativePG with the
  Barman Cloud plugin, Strimzi Kafka (KRaft node pools, JMX metrics), Kafka
  Connect with a Debezium build example, RabbitMQ operators, Valkey,
  kube-prometheus-stack, Loki (14d retention default), Tempo, Grafana with
  curated Kubernetes dashboards, Alloy, Reloader, optional ZITADEL and
  optional Infisical.
- Curated PrometheusRules for Kafka, CloudNativePG and cert-manager, plus
  chart-native Loki alerts, recording rules and dashboards.
- CI: shellcheck, Terraform fmt/validate/tflint for every stack, Helmfile
  render validated with kubeconform against upstream CRD schemas.
- End-to-end suite on kind: installs the full base, traverses the Envoy
  data-plane Service and asserts HTTP through the gateway, certificate
  issuance, CNPG, Kafka, Valkey and the monitoring resources.
- Renovate configuration keeping every pinned component fresh.

[Unreleased]: https://github.com/pyahu/open-cluster-foundation/compare/v2026.9.0...HEAD
[2026.9.0]: https://github.com/pyahu/open-cluster-foundation/releases/tag/v2026.9.0
