# Zero-Trust CI/CD Architecture

## Overview

This project demonstrates a security-focused CI/CD pipeline that builds,
scans, publishes, signs, and deploys a containerized application to Kubernetes.

## Architecture

```text
Developer
   |
   v
GitHub Repository
   |
   v
GitHub Actions CI/CD
   |
   +--> Build container image
   |
   +--> Grype vulnerability scan
   |       |
   |       +--> Fail when High/Critical threshold is met
   |
   +--> Generate SPDX JSON SBOM
   |
   +--> Publish validated image to GHCR
   |
   +--> Cosign keyless signing using GitHub OIDC
           |
           v
     GitHub Container Registry
           |
           v
      Kubernetes API
           |
           +--> Kyverno
           |      Verify trusted image signature and workflow identity
           |
           +--> Gatekeeper
           |      Restrict allowed container registries
           |
           v
    zero-trust-demo namespace
           |
           +--> Non-root application container
           +--> Read-only root filesystem
           +--> Dropped Linux capabilities
           +--> CPU and memory limits
           +--> Liveness and readiness probes
           +--> ClusterIP Service
```

## Security controls

- Vulnerability scanning with a configured severity threshold.
- SPDX JSON software bill of materials (SBOM).
- GHCR image publishing.
- Keyless Cosign signing using GitHub Actions OIDC.
- Kyverno image signature and identity verification.
- Gatekeeper registry restrictions.
- Non-root container execution.
- Read-only root filesystem and dropped capabilities.
- Disabled privilege escalation and automatic service-account token mounting.
- Kubernetes resource requests, limits, and health probes.

## Important distinction

A successful build or deployment does not by itself prove that every
security control has been tested. Negative admission tests and runtime
validation should be recorded separately.

## Current deployment

- Kubernetes namespace: `zero-trust-demo`
- Deployment: `zero-trust-demo`
- Service: `zero-trust-demo`
- Service type: `ClusterIP`
- Application port: `8080`
- Container UID/GID: `10001:10001`
