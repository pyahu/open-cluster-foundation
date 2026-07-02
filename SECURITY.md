# Security Policy

## Reporting a vulnerability

Please do not report security issues through public GitHub issues.

Use GitHub private vulnerability reporting: **Security → Report a
vulnerability** on this repository. We will acknowledge the report within a
few business days and keep you informed of the fix progress.

## Scope

This repository ships infrastructure blueprints, not a hosted service.
Relevant reports include:

- Defaults that expose clusters or workloads (network rules, Pod Security,
  credentials handling, TLS configuration).
- Scripts that could leak secrets or execute untrusted input.
- Pinned component versions with known exploitable vulnerabilities where the
  blueprint blocks the upgrade path.

Vulnerabilities in the upstream components themselves (Kubernetes, Envoy
Gateway, Strimzi, etc.) should be reported to their projects; we track pinned
versions through Renovate.

## Supported versions

Only the latest release receives fixes. There are no backports.
