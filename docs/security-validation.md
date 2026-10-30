# Security Validation and Test Evidence

## 1. Overview

This document records the security validation results for the **Zero Trust CI/CD Pipeline** project.

It covers automated Kubernetes validation, container image signature verification, admission-policy enforcement, CI security evidence, and operational checks.

The validation demonstrates that:

- Kubernetes workloads meet the configured container security requirements.
- Kyverno verifies container image signatures against a trusted GitHub Actions workflow identity.
- Gatekeeper restricts workloads to approved container registries.
- Unsigned images within the protected repository scope are rejected.
- Trusted signed images are accepted by the production admission policy.
- CI generates vulnerability scan reports and a Software Bill of Materials (SBOM).

The validation results represent the tested environment and configuration at the time of execution.

## 2. Validation Environment

| Component | Configuration |
|---|---|
| Kubernetes distribution | Kind |
| Kubernetes context | `kind-zero-trust` |
| Namespace | `zero-trust-demo` |
| Admission policy | `verify-zero-trust-demo` |
| Registry constraint | `allow-ghcr-only` |
| CI platform | GitHub Actions |
| Container registry | GitHub Container Registry (GHCR) |
| Image signing | Cosign keyless signing |
| Image verification | Kyverno |
| Registry enforcement | OPA Gatekeeper |
| Vulnerability scanner | Grype |
| SBOM format | SPDX JSON |

## 3. Automated Validation Results

<details>
<summary>Latest automated validation summary</summary>

**8 checks passed, 0 failed.**

</details>

The latest local validation suite completed successfully, with all eight checks passing.

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

### 3.1 Run the Complete Validation Suite

Run the following command from the repository root:

```powershell
.\scripts\validate-security.ps1
```

The complete validation script checks the current cluster state, admission controllers, workload configuration, application health, and security-policy behavior.

### 3.2 Run Focused Image Admission Tests

To independently test image signature admission behavior, run:

```powershell
.\scripts\test-image-admission.ps1
```

The focused regression script verifies that the current Kubernetes context is:

```text
kind-zero-trust
```

**Prerequisites**

Both scripts require:

- The intended Kind cluster to be running.
- The Kubernetes context to point to the expected cluster.
- Kyverno and Gatekeeper controllers to be available.
- The required admission policies to be installed.
- Network access to the container registry when image retrieval is required.

The focused image-admission tests use Kubernetes server-side dry runs. They validate admission decisions without creating persistent test Pods.

## 4. Image Signature Verification

### 4.1 Production Verification Policy

The production Kyverno policy verifies container image signatures against the trusted GitHub Actions workflow identity.

The expected signer identity is:

```text
https://github.com/cloudwithnikhil/zero-trust-pipeline/.github/workflows/ci.yml@refs/heads/main
```

The expected OIDC issuer is:

```text
https://token.actions.githubusercontent.com
```

This establishes a trust relationship between the published container image and the authorized GitHub Actions workflow.

The verification policy is designed to ensure that images within its configured repository scope are admitted only when they satisfy the required signature verification conditions.

### 4.2 Positive Test: Trusted Signed Image

**Result: Accepted as expected**

The published container image associated with the following Git commit was successfully accepted by the production image-verification policy.

**Commit:**

```text
aa772d516a8238a10e589f06cb88f169e6865ff3
```

**Verified image digest:**

```text
sha256:cd4f2146032c50950a6d7df0d60a308ec510ab00b129ba589c9f43e03856e7ab
```

The admission test used:

```bash
kubectl create --dry-run=server
```

The Kubernetes API server accepted the request after the production Kyverno policy verified the trusted image.

Because the test used server-side dry-run mode, no persistent test Pod was created.

This confirms that the tested image satisfied the configured signature-verification requirements.

### 4.3 Negative Test: Unsigned Image

**Result: Rejected as expected**

The following image was used for the unsigned-image admission test:

```text
ghcr.io/cloudwithnikhil/zero-trust-pipeline:unsigned-test-20261029113243
```

The image was published independently without a Cosign signature.

The image was within the protected repository scope of the production Kyverno policy.

When the admission request was submitted, Kyverno rejected it with the expected policy message:

```text
Image must have a valid Cosign signature from the trusted GitHub Actions workflow.
```

This is a meaningful negative security test because:

1. The image reference matched the protected repository scope.
2. The image did not have the required Cosign signature.
3. Kyverno rejected the admission request.
4. The rejection matched the expected signature-verification policy message.

This demonstrates that the production policy enforces signature verification for the tested image scope.

### 4.4 Additional Negative-Test Observations

Additional tests were performed to distinguish actual signature-policy enforcement from unrelated admission failures.

| Test scenario | Observed result | Interpretation |
|---|---|---|
| Nonexistent image tag | Denied with `MANIFEST_UNKNOWN` from GHCR | Registry lookup failure; not proof of signature-policy enforcement |
| Image outside configured Kyverno image-reference scope | Accepted | Expected scope behavior; does not test signature rejection |
| Intentionally incorrect signer identity | Denied by Kyverno | Demonstrates rejection when the signer identity does not match the configured trust requirement |
| Unsigned image inside protected repository scope | Denied by Kyverno | Confirms signature-policy enforcement for the tested scope |

The temporary policy used for the incorrect-signer-identity test was removed after testing.

The production image-verification policy remained in place.

**Important:** A rejected image request does not automatically demonstrate that signature verification worked. The rejection reason must be examined to confirm that the intended security control caused the denial.

## 5. CI Security Evidence

### 5.1 GitHub Actions Execution

GitHub Actions run:

```text
40740937471
```

completed successfully, with both jobs passing.

The workflow included the following jobs:

1. **Build, Scan and Generate SBOM**
2. **Publish to GHCR and Sign with Cosign**

The successful execution provides evidence that the configured CI pipeline completed its build, vulnerability-scanning, SBOM-generation, image-publishing, and signing stages.

### 5.2 Generated Security Evidence

| Evidence | Purpose | Status |
|---|---|---|
| Grype JSON report | Machine-readable vulnerability scan results | Produced by successful CI run |
| SPDX JSON SBOM | Inventory of software components in the container image | Produced by successful CI run |
| GitHub Actions job summary | Build, SBOM, and scan step outcomes | Successful run |
| Published image digest | Identifies the immutable image reference | Confirmed |
| Cosign signing and verification evidence | Records image signing and signature verification | Confirmed |

### 5.3 Expected Workflow Artifacts

The workflow is configured to produce the following artifacts:

```text
security-evidence
zero-trust-demo-sbom
validated-container-image
image-signing-evidence
```

These artifacts provide supporting evidence for the security checks performed during CI execution.

Artifact availability and retention depend on the GitHub Actions workflow configuration.

### 5.4 Vulnerability Scanning

Grype is used to scan the built container image for known vulnerabilities.

The scan is configured with:

```yaml
severity-cutoff: high
fail-build: true
```

The CI job is configured to fail when the vulnerability scan meets the configured severity threshold.

This makes vulnerability scanning a build-validation control rather than an informational step alone.

The generated Grype JSON report provides machine-readable scan results for further review.

A successful CI run confirms that the configured scan step completed successfully. It should not be interpreted as proof that the image contains no vulnerabilities.

### 5.5 SBOM Generation

The pipeline generates a Software Bill of Materials (SBOM) in SPDX JSON format.

The SBOM provides an inventory of software components included in the container image.

It supports:

- Software component visibility.
- Vulnerability investigation.
- Dependency tracking.
- Software supply-chain transparency.
- Future security and compliance reviews.

### 5.6 Image Publishing and Signing

The publish-and-sign job runs on pushes to the `main` branch after the validation job succeeds.

The pipeline:

1. Publishes the validated container image to GHCR.
2. Identifies the published image using its immutable digest.
3. Signs the image by digest using Cosign keyless signing.
4. Uses GitHub Actions OIDC identity for signing.
5. Verifies the signature against the expected workflow identity and OIDC issuer.

Signing by immutable digest ensures that the signature is associated with a specific image artifact rather than relying only on a mutable tag.

The expected signing identity and OIDC issuer are documented in [Section 4](#4-image-signature-verification).

## 6. Kubernetes Admission Controls

The project uses two independent admission controls to enforce container image security.

### 6.1 Kyverno: Image Signature Verification

Kyverno verifies that images within the configured protected repository scope have a valid Cosign signature from the trusted GitHub Actions workflow identity.

The policy is responsible for:

- Verifying image signatures.
- Checking the expected signer identity.
- Checking the expected OIDC issuer.
- Rejecting unsigned or incorrectly signed images within its configured scope.

### 6.2 OPA Gatekeeper: Registry Restriction

Gatekeeper enforces the configured container registry restriction.

The registry constraint is:

```text
allow-ghcr-only
```

The validation suite confirmed that an image from the following registry was denied:

```text
docker.io/library/nginx:latest
```

This verifies that the tested workload was prevented from using an image outside the allowed registry configuration.

### 6.3 Independent Security Responsibilities

| Security control | Responsibility |
|---|---|
| Kyverno | Verify image signatures and trusted workflow identity |
| OPA Gatekeeper | Enforce the allowed container registry |
| Grype | Scan container images for known vulnerabilities |
| Cosign | Sign and verify container image signatures |
| GitHub Actions OIDC | Provide the workload identity used for keyless signing |

These controls address different security requirements. Passing one control does not prove that the others are functioning correctly.

## 7. Workload Security Validation

The application is deployed in the following namespace:

```text
zero-trust-demo
```

The workload uses Kubernetes security settings designed to reduce container privileges and limit its runtime attack surface.

### 7.1 Container Security Context

The application container is configured with the following protections:

| Security setting | Expected configuration | Security purpose |
|---|---|---|
| Non-root execution | UID/GID `10001:10001` | Prevents the application from running as root |
| Read-only root filesystem | Enabled | Prevents modification of the container root filesystem |
| Privilege escalation | Disabled | Prevents processes from gaining additional privileges |
| Linux capabilities | Dropped | Reduces unnecessary kernel-level privileges |
| Service account token automount | Disabled | Prevents automatic mounting of an unnecessary Kubernetes API token |
| CPU limits | Configured | Restricts CPU consumption |
| Memory limits | Configured | Restricts memory consumption |

### 7.2 Application Health

The application exposes a health endpoint:

```text
/health
```

The validation suite confirmed that the endpoint returned:

```json
{
  "status": "healthy"
}
```

This confirms that the application health check responded successfully during the test.

### 7.3 Kubernetes Service Exposure

The application is exposed through an internal Kubernetes ClusterIP Service.

| Setting | Configuration |
|---|---|
| Deployment | `zero-trust-demo` |
| Service | `zero-trust-demo` |
| Namespace | `zero-trust-demo` |
| Service type | `ClusterIP` |
| Application port | `8080` |

A ClusterIP Service provides internal cluster connectivity rather than directly exposing the application through a public LoadBalancer or NodePort.

## 8. Operational Notes and Limitations

The following operational observations apply to the tested environment:

- The trusted image was pinned to an immutable digest during admission testing.
- The application is exposed through an internal ClusterIP Service.
- The application health endpoint returned a healthy response.
- Gatekeeper registry enforcement and Kyverno signature verification are separate controls and should be tested independently.
- The automated validation script checks current cluster state and policy behavior.
- Automated validation does not replace reviewing the underlying workflow, policy definitions, vulnerability findings, or image-signing evidence.
- Admission regression tests use server-side dry runs and do not create persistent test Pods.
- The local `artifacts/` directory is intended for local security-test evidence and should remain excluded from Git unless specific, sanitized evidence is deliberately selected for publication.

### 8.1 Interpretation of Test Results

The reported **8 passed, 0 failed** result represents the latest execution of the local automated validation suite.

It does not imply that every possible attack scenario, Kubernetes configuration, container vulnerability, or supply-chain risk has been tested.

The results should be interpreted as evidence that the documented controls behaved as expected under the tested conditions.

For ongoing validation, the test suite should be rerun after changes to:

- GitHub Actions workflows.
- Container build configuration.
- Image-signing configuration.
- Kyverno policies.
- Gatekeeper constraints.
- Kubernetes workload manifests.
- Application container security settings.

## 9. Reproducing the Validation

To reproduce the local security checks, use the following commands from the repository root.

**Step 1: Confirm the Kubernetes context**

```powershell
kubectl config current-context
```

Expected output:

```text
kind-zero-trust
```

**Step 2: Confirm the application namespace**

```powershell
kubectl get namespace zero-trust-demo
```

**Step 3: Check the admission controllers**

```powershell
kubectl get pods -n kyverno
kubectl get pods -n gatekeeper-system
```

**Step 4: Run the complete security validation**

```powershell
.\scripts\validate-security.ps1
```

**Step 5: Run the focused image-admission regression tests**

```powershell
.\scripts\test-image-admission.ps1
```

Review the script output and confirm that the expected admission decisions and workload checks are reported.

## 10. Security Validation Summary

The latest recorded validation demonstrates the following:

| Security area | Validation outcome |
|---|---|
| CI build and validation | Successful |
| Vulnerability scanning | Completed successfully |
| SPDX SBOM generation | Completed successfully |
| GHCR image publishing | Confirmed |
| Cosign keyless signing | Confirmed |
| Trusted workflow identity verification | Confirmed |
| Kyverno admission policy | Passed |
| Unsigned image rejection | Passed |
| Incorrect signer identity rejection | Passed |
| Gatekeeper registry restriction | Passed |
| Kubernetes workload hardening | Passed |
| Application health check | Passed |

**Overall local validation result: 8 passed, 0 failed.**

The project demonstrates a layered container supply-chain security approach in which image validation, vulnerability scanning, SBOM generation, trusted image signing, Kubernetes admission enforcement, and workload hardening work together.

The validation evidence supports the intended Zero Trust deployment model: container images are not trusted solely because they are available in a registry; they must satisfy the configured security and identity requirements before admission.

---

**Project:** Zero Trust CI/CD Pipeline  
**Repository:** [cloudwithnikhil/zero-trust-pipeline](https://github.com/cloudwithnikhil/zero-trust-pipeline)  
**CI Platform:** GitHub Actions  
**Container Registry:** GitHub Container Registry (GHCR)  
**Kubernetes Environment:** Kind  
**Documentation:** `docs/security-validation.md`