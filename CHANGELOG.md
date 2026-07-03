# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); releases use calver
tags (`vYYYY.M.PATCH`).

## [Unreleased]

### Added

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
- Renovate configuration keeping every pinned component fresh.
