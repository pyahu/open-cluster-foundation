---
title: Architecture
description: Understand Open Cluster Foundation ownership and installation layers.
---

OCF separates cloud resources, shared cluster services and application resources. Each layer has a different owner and change cycle.

<div class="ocf-layers">
  <div class="ocf-layer"><strong>Applications</strong><p>Your manifests, namespaces, databases, topics, queues and routes.</p></div>
  <div class="ocf-layer"><strong>Kubernetes foundation</strong><p>Helmfile profiles for edge, TLS, GitOps, observability and optional service operators.</p></div>
  <div class="ocf-layer"><strong>Cloud foundation</strong><p>Terraform for the VCN, subnets, security rules, OKE, Bastion and node pools.</p></div>
  <div class="ocf-layer"><strong>Provider</strong><p>OCI today. Additional clouds must implement the same provider contract.</p></div>
</div>

## Cloud ownership

Terraform owns the resources declared by the OCI foundation. A small number of security list fields are intentionally shared with the OCI cloud controller because Kubernetes Services need to manage NodePort paths. These lifecycle boundaries are documented and tested.

## Cluster service ownership

Helmfile selects releases by profile. The installer orders CRDs and controllers before dependent resources, limits installation concurrency and records a checkpoint after a successful apply.

## Application ownership

OCF supplies examples for PostgreSQL, Kafka, RabbitMQ, probes and network access. Teams copy and adapt those resources. OCF does not choose application capacity, retention or recovery objectives.

## Why the split matters

- A Kubernetes profile can evolve without rebuilding the cloud network.
- A new provider can implement the cloud contract without copying the service layer.
- Operators can review Terraform plans separately from rendered Kubernetes changes.
- Existing clusters keep a compatibility path instead of silently receiving fresh defaults.

Read the [implementation decisions](https://github.com/pyahu/open-cluster-foundation/blob/main/docs/implementation-decisions.md) for the rationale behind safety sensitive defaults and ownership boundaries.
