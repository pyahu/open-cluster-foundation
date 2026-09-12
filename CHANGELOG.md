# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); releases use calver
tags (`vYYYY.M.PATCH`).

## [Unreleased]

### Added

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
