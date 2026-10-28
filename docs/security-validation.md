# Security Validation

## Environment

- Kubernetes context: `kind-zero-trust`
- Namespace: `zero-trust-demo`
- Admission policy: `verify-zero-trust-demo`
- Registry constraint: `allow-ghcr-only`

## Checks Completed

| Check | Result | Evidence |
|---|---|---|
| Image build and CI workflow | Passed | Successful GitHub Actions run |
| Kyverno policy readiness | Passed | `conditionStatus.ready: true` |
| Trusted image admission dry run | Accepted | Request resolved to an immutable image digest |
| Deployment admission dry run | Passed | Deployment and Service accepted by API server |
| Kubernetes rollout | Passed | Deployment reported successfully rolled out |
| Application Pod | Passed | Pod reached `Running` and `Ready` |
| Non-root execution | Passed | Container process UID/GID `10001:10001` |
| Privilege escalation | Disabled | `allowPrivilegeEscalation: false` |
| Root filesystem | Read-only | `readOnlyRootFilesystem: true` |
| Linux capabilities | Dropped | `capabilities.drop: ["ALL"]` |
| Service-account token automount | Disabled | `automountServiceAccountToken: false` |
| Resource limits | Configured | CPU and memory limits present |
| HTTP health endpoint | Passed | Returned `status: healthy` |
| Gatekeeper controller | Available | Controller Deployment has an available replica |
| Registry restriction negative test | Rejected | Gatekeeper denied `docker.io/library/nginx:latest` |
| Wrong workflow identity negative test | Rejected | Kyverno denied the request under a deliberately incorrect signer identity |
| Automated validation script | Passed | `scripts/validate-security.ps1`: 6 passed, 0 failed |

## Signature Verification Negative Test

A request using a nonexistent image tag was denied because GHCR returned `MANIFEST_UNKNOWN`. This was not proof of signature rejection.

A request using `ghcr.io/stefanprodan/podinfo:latest` was accepted because that image was outside the Kyverno policy's configured image-reference scope. This was not a negative signature test.

A separate test used the project's existing published image with a temporary Kyverno policy configured for an intentionally incorrect GitHub Actions workflow identity. Kyverno denied the admission request with the policy's signature-verification validation message.

This demonstrates rejection when the signer identity does not match the configured trusted identity. A dedicated test using an existing, unsigned image within the protected repository scope remains outstanding.

The temporary test policy was deleted after the test. The production policy `verify-zero-trust-demo` remained in place and ready.

## Automated Validation

Run the following command from the repository root with the Kind cluster and admission controllers available:

```powershell
.\scripts\validate-security.ps1
```

The script checks:

- Kyverno image-verification policy readiness.
- Gatekeeper controller availability.
- Application Deployment availability.
- Workload security context and resource limits.
- Application health endpoint.
- Rejection of a Docker Hub image by Gatekeeper.

Latest recorded result: **6 passed, 0 failed**.


## CI Security Evidence

The GitHub Actions workflow is configured to produce the following evidence:

| Evidence | Purpose | Status |
|---|---|---|
| Grype JSON report | Machine-readable vulnerability scan results | Pending successful workflow run |
| SPDX JSON SBOM | Inventory of software components in the container image | Pending successful workflow run |
| GitHub Actions job summary | Build, SBOM, and scan step outcomes | Pending successful workflow run |
| Published image digest | Identifies the immutable image reference | Pending successful publish job |
| Cosign verification output | Verifies the image signature against the expected GitHub Actions identity and OIDC issuer | Pending successful publish job |

Expected workflow artifacts:

- `security-evidence`
- `zero-trust-demo-sbom`
- `validated-container-image` (short retention for publishing)
- `image-signing-evidence`

The vulnerability scan is configured with `severity-cutoff: high` and `fail-build: true`. The CI job should fail if the scan meets the configured severity threshold.

The publish-and-sign job runs only for pushes to `main`, after the validation job succeeds. It signs the published image by immutable digest and then verifies the signature.

**Evidence status:** These are configured workflow behaviors, not confirmed results. Update this section after reviewing an actual successful GitHub Actions run and downloading its artifacts.

The local Kind cluster admission tests are separate from the GitHub Actions workflow. They must continue to be validated independently.


## Operational Notes

- The trusted image was pinned to a digest during admission.
- The application is exposed through an internal ClusterIP Service.
- The successful HTTP health response confirms the endpoint is operational.
- Gatekeeper registry enforcement and Kyverno signature verification are separate controls and should be tested independently.
- The automated script verifies current cluster state; it does not replace the separate admission-negative tests documented above.
