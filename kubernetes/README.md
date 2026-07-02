# Kubernetes

Provider-agnostic Kubernetes layers.

Current modules:

| Module | Purpose |
| --- | --- |
| [`production-base`](production-base/README.md) | Edge, certificates, GitOps, database operators, messaging operators and observability baseline. |

Start with Terraform provider foundations under [`../terraform`](../terraform)
when you need a new cluster. Use this directory after kubeconfig is ready.
