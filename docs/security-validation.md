# Security Validation

## Environment

- Kubernetes context: `kind-zero-trust`
- Namespace: `zero-trust-demo`
- Admission policy: `verify-zero-trust-demo`
- Registry constraint: `allow-ghcr-only`
- CI platform: GitHub Actions
- Container registry: GitHub Container Registry (GHCR)

## Automated Validation Results

Latest local validation result: **8 passed, 0 failed**.

| Check | Result | Evidence |
|---|---|---|
| Kyverno image-verification policy | Passed | `conditionStatus.ready: true` |
| Gatekeeper controller | Passed | Controller Deployment has an available replica |
| Application Deployment | Passed | At least one available replica |
| Workload security context | Passed | Non-root execution, read-only root filesystem, disabled privilege escalation, dropped capabilities, token automount disabled, and CPU/memory limits |
| Application health endpoint | Passed | `/health` returned `status: healthy` |
| Registry restriction | Passed | Gatekeeper denied `docker.io/library/nginx:latest` |
| Unsigned image admission | Rejected as expected | Kyverno denied an unsigned image within the protected repository scope |
| Trusted signed image admission | Accepted as expected | Kyverno admitted the trusted signed image during a server-side dry run |

Run the complete validation suite from the repository root:

```powershell
.\scripts\validate-security.ps1
```

Run the focused image-admission regression tests independently:

```powershell
.\scripts\test-image-admission.ps1
```

Both scripts require the intended Kind cluster and admission controllers to be available. The focused regression script checks that the current Kubernetes context is `kind-zero-trust`.

## Image Signature Verification

The production Kyverno policy verifies image signatures against the trusted GitHub Actions workflow identity and GitHub Actions OIDC issuer.

Expected signer identity:

`https://github.com/cloudwithnikhil/zero-trust-pipeline/.github/workflows/ci.yml@refs/heads/main`

Expected OIDC issuer:

`https://token.actions.githubusercontent.com`

### Positive test: trusted signed image

The published image associated with commit `aa772d516a8238a10e589f06cb88f169e6865ff3` was accepted by the production image-verification policy.

Verified image digest:

`sha256:cd4f2146032c50950a6d7df0d60a308ec510ab00b129ba589c9f43e03856e7ab`

The admission test used `kubectl create --dry-run=server`. The API server accepted the request without creating a persistent test Pod.

### Negative test: unsigned image

The existing test image was:

`ghcr.io/cloudwithnikhil/zero-trust-pipeline:unsigned-test-20261029113243`

The image was published independently without a Cosign signature. The production Kyverno policy rejected the admission request with the expected message:

`Image must have a valid Cosign signature from the trusted GitHub Actions workflow.`

This is a meaningful negative test because the image was within the protected repository scope and the rejection matched the signature-policy message.

### Other negative-test observations

- A nonexistent image tag was denied because GHCR returned `MANIFEST_UNKNOWN`. That alone is not proof of signature-policy enforcement.
- An image outside the configured Kyverno image-reference scope was accepted. That result did not test signature rejection.
- A separate test with an intentionally incorrect signer identity was denied by Kyverno.
- The temporary policy used for the incorrect-identity test was removed afterward. The production policy remained in place.

## CI Security Evidence

GitHub Actions run `40740937471` completed successfully, with both jobs passing:

- **Build, Scan and Generate SBOM**
- **Publish to GHCR and Sign with Cosign**

The workflow produced the following security evidence:

| Evidence | Purpose | Status |
|---|---|---|
| Grype JSON report | Machine-readable vulnerability scan results | Produced by successful CI run |
| SPDX JSON SBOM | Inventory of software components in the container image | Produced by successful CI run |
| GitHub Actions job summary | Build, SBOM, and scan step outcomes | Successful run |
| Published image digest | Identifies the immutable image reference | Confirmed |
| Cosign signing and verification evidence | Records image signing and signature verification | Confirmed |

Expected workflow artifacts:

- `security-evidence`
- `zero-trust-demo-sbom`
- `validated-container-image`
- `image-signing-evidence`

The vulnerability scan is configured with `severity-cutoff: high` and `fail-build: true`. The CI job is configured to fail when the scan meets the configured severity threshold.

The publish-and-sign job runs on pushes to `main` after the validation job succeeds. It signs the published image by immutable digest and verifies the signature against the expected GitHub Actions identity and OIDC issuer.

The local Kind admission tests are separate from the GitHub Actions workflow and must continue to be validated independently.

## Operational Notes

- The trusted image was pinned to an immutable digest during admission.
- The application is exposed through an internal ClusterIP Service.
- The application health endpoint returned a healthy response.
- Gatekeeper registry enforcement and Kyverno signature verification are separate controls and should be tested independently.
- The automated validation script checks current cluster state and policy behavior. It does not replace reviewing the underlying workflow, policy definitions, scan findings, or signing evidence.
- Admission regression tests use server-side dry runs and do not create persistent test Pods.
- The local `artifacts/` directory is intended for local security test evidence and should remain excluded from Git unless specific, sanitized evidence is deliberately selected for publication.
