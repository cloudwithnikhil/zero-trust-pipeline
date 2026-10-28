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