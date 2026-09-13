# Remediation report

Assessment date: 2026-09-13
First tested release: [`v2026.9.0`](https://github.com/pyahu/open-cluster-foundation/releases/tag/v2026.9.0)

## Executive assessment

Open Cluster Foundation is worth publishing and maintaining as a community
project. It solves a real platform-engineering problem: the managed Kubernetes
control plane is only the beginning of a production cluster, while edge,
certificates, observability, stateful operators, access control, lifecycle and
recovery are usually assembled independently and inconsistently.

The repository is now a strong OCI-first production blueprint with a
provider-agnostic Kubernetes layer. It is not yet a multi-cloud product: OCI/OKE
is the only implemented and live-observed cloud foundation. The provider
contract makes additional implementations feasible, but a contract is not a
substitute for provisioning and operating another provider.

The honest positioning is therefore:

- Production-oriented and production-used, with compatibility controls for an
  existing OCI installation.
- Fully functional as an OCI foundation and reusable Kubernetes service layer.
- Suitable for community adoption by teams prepared to own cloud cost,
  identity, DNS, backups, capacity and on-call operations.
- Not a production guarantee, managed service, universal compliance baseline or
  finished multi-cloud implementation.

Community publication is recommended with those boundaries kept prominent.

## Final evidence

The release commit `80471583a8bbcd3c8e2a2283f76acc7a9d1f9594` passed:

- [CI](https://github.com/pyahu/open-cluster-foundation/actions/runs/34732453534):
  documentation, scripts and unit tests, Terraform, Kubernetes schema/rendering
  and supply chain.
- [E2E](https://github.com/pyahu/open-cluster-foundation/actions/runs/34732453580):
  a disposable Kubernetes 1.36.1 cluster exercising edge authorization,
  NetworkPolicy isolation, TLS issuance, Kafka, Kafka Connect, Valkey,
  PostgreSQL backup and physical restore, logs and traces.
- [CodeQL](https://github.com/pyahu/open-cluster-foundation/actions/runs/34732453538):
  GitHub Actions analysis.

The release was then consumed independently in two ways: a shallow clone by
the annotated tag resolved to the tested commit, and Terraform successfully ran
`init -from-module` plus `validate` against the documented Git source and tag.
All 147 Markdown links and all README badges returned successful responses.

The repository enables dependency alerts and security updates, private
vulnerability reporting, secret scanning, push protection, validity checks,
non-provider secret detection and CodeQL. There were no open Dependabot, secret
scanning or code scanning alerts at assessment time. Discussions and structured
issue forms are enabled. Release immutability is enabled for releases created
after `v2026.9.0`; GitHub applies that setting only to future releases.

## Existing OCI installation

The production reference cluster was inspected with explicit-context,
read-only commands. No apply, patch, label, scale, rollout, Helm mutation or
Terraform operation was executed against it.

| Signal | Observation |
| --- | --- |
| Kubernetes API | `/readyz` returned `ok` |
| Version | server 1.36.1; client 1.36.2 |
| Nodes | 11 total, 11 Ready, arm64 |
| Deployments and StatefulSets | 56 total, 56 at desired readiness |
| Pods | 189 Running or Succeeded, 0 Pending, 0 Failed |
| Storage | 2 StorageClasses, exactly 1 default |
| Helm | 14 releases, 14 deployed, 0 failed |
| Gateway API | 1 GatewayClass accepted; 1 Gateway programmed |
| TLS | 19 Certificates, 19 Ready |
| CloudNativePG | 2 clusters, 2 Ready |
| Kafka | 2 clusters and 3 Kafka Connect resources, all Ready |
| Metrics API | metrics available for all 11 nodes |
| Monitoring | 40 PrometheusRules, 26 ServiceMonitors, 14 PodMonitors, 9 Probes |

The cluster has no `open-cluster-foundation-installation` checkpoint and is
therefore classified as a legacy installation. That is expected because this
remediation deliberately never mutated production. Automatic upgrade detection
preserves its former profile and access behavior. Hardened network,
observability, identity and cache defaults require their documented staged
migrations; they must not be inferred from the health observations above.

## Remediation record

| Task | Result |
| --- | --- |
| T00 | Inventoried source, automation and live compatibility without mutation. |
| T01 | Added non-CI instance-value and placeholder preflights plus shell regression tests. |
| T02 | Added fresh/legacy/managed modes and a durable installation-state contract. |
| T03 | Introduced starter, production, production-data and compatibility-safe profiles. |
| T04 | Aligned Terraform and CloudNativePG database-node scheduling contracts. |
| T05 | Restricted public Gateway attachment with a staged namespace-label migration. |
| T06 | Added default-deny policies, minimum allowlists and an explicit migration gate. |
| T07 | Restricted observability discovery and ingestion to trusted namespaces and identities. |
| T08 | Made fresh Argo CD and Grafana access SSO-only with strict group mapping. |
| T09 | Added Valkey ACL persistence and hardened optional identity/secrets services. |
| T10 | Added explicit HA and durable-observability profiles, PDBs and capacity/cost guidance. |
| T11 | Expanded E2E coverage to real data, authorization, isolation, logging and tracing flows. |
| T12 | Added PostgreSQL backup/restore and production-topology Kafka validation. |
| T13 | Pinned Actions and external inputs; added image, vulnerability and IaC policy checks. |
| T14 | Hardened OCI networking, logging, state, kubeconfig and autoscaling contracts. |
| T15 | Made partial installation recovery and profile-aware orchestration resumable. |
| T16 | Established a tested provider contract and corrected the multi-cloud claim. |
| T17 | Generated compatibility/component references and documented lifecycle recovery. |
| T18 | Moved operational rationale into documentation and enforced comment-free source. |
| T19 | Enabled community/security settings and published the first tested release. |
| T20 | Repeated the full suite, audited production read-only and published this report. |

## Code and maintenance assessment

The strongest implementation qualities are explicit state transitions, pinned
dependencies, strict input validation, bounded installation concurrency,
schema validation against actual CRDs, realistic E2E data paths and careful
compatibility gates. The source is readable through names and small library
functions; safety-sensitive reasoning is centralized in
[Implementation decisions](implementation-decisions.md). Generated references
remove the most common form of documentation drift.

The main shell orchestrator is necessarily complex and remains the part most
likely to become difficult to evolve. New behavior should continue moving into
focused library functions with unit tests instead of growing one procedural
entrypoint. Provider implementations must remain independently testable and
must not add provider-specific behavior to the Kubernetes base.

Trunk-based development intentionally leaves `main` without pull-request branch
protection. This matches the project's declared workflow, but it means local
tests and fast repair of a failed post-push pipeline are operational controls,
not preventative gates. Commits and the first annotated release tag are not
cryptographically signed. Signing future release tags and publishing build
provenance would further improve consumer trust.

## Remaining limitations and priorities

1. Implement and operate a second cloud provider before describing the project
   as multi-cloud. Require the same contract evidence, E2E coverage and a live
   read-only observation.
2. Extract and publish the OCI Terraform module from its required dedicated
   repository before advertising the Registry address.
3. Add provider-provisioning integration tests in disposable cloud accounts.
   Kind validates the Kubernetes layer but cannot prove OCI network creation,
   IAM, load balancer behavior or destructive lifecycle on every change.
4. Add signed tags, artifact attestations and SBOMs for future releases. Release
   immutability is already enabled for those future publications.
5. Exercise the documented full disaster-recovery and ordered-uninstall drills
   on a disposable provider cluster. The project deliberately has no generic
   one-command rollback or uninstall because stateful data requires explicit
   retention decisions.
6. Keep the production reference cluster on the legacy path until each staged
   migration is reviewed independently. Healthy current state is not permission
   to force new defaults onto it.

## Publication verdict

Publish and promote the project as an OCI-first, production-oriented Kubernetes
foundation with a portable service layer and an open provider contract. The
combination of live use, compatibility preservation, full-stack E2E tests and
operational documentation is genuinely useful to the community. Avoid the
phrases “turnkey production” and “multi-cloud implementation” until the
remaining provider and recovery evidence exists.
