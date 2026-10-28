# Zero-Trust CI/CD Pipeline

A DevSecOps portfolio project demonstrating secure container delivery using GitHub Actions, Docker, SBOM generation, Cosign image signing, Kubernetes, Kyverno, and OPA Gatekeeper.

## Architecture

```text
Developer → GitHub → GitHub Actions
                         |
                         v
              Build & Security Scan
                         |
                         v
                  SBOM Generation
                         |
                         v
               GHCR Container Image
                         |
                         v
                 Cosign Signing
                         |
                         v
                 Kubernetes Cluster
                    /         \
               Kyverno     Gatekeeper
             Verify Sign.  Allow Registry
                    \         /
                     Admission


## Security Validation

Run the automated security checks against the configured Kubernetes cluster:

```powershell
.\scripts\validate-security.ps1
```

The validation script checks:

- Kyverno `ImageValidatingPolicy` readiness.
- Gatekeeper controller availability.
- Application Deployment availability.
- Workload hardening: non-root execution, read-only root filesystem, disabled privilege escalation, dropped Linux capabilities, disabled service-account token automount, and resource limits.
- Application health endpoint.
- Rejection of an image from Docker Hub by the Gatekeeper registry policy.

**Latest local validation:** 6 checks passed, 0 failed.

### Admission Policy Testing

A separate negative test attempted to admit the project's published image using a deliberately incorrect GitHub Actions workflow identity. Kyverno denied the request, demonstrating that the image did not satisfy that identity requirement.

This test does not replace a dedicated test using an existing unsigned image.
