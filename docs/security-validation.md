# Security Validation

## Environment

- Kubernetes context: `kind-zero-trust`
- Namespace: `zero-trust-demo`
- Admission policy: `verify-zero-trust-demo`
- Registry constraint: `allow-ghcr-only`

## Checks completed

| Check | Result | Evidence |
|---|---|---|
| Image build and CI workflow | Passed | Successful GitHub Actions run |
| Kyverno policy readiness | Passed | `kubectl get imagevalidatingpolicies` |
| Trusted image admission dry run | Accepted | Pod request resolved to an immutable image digest |
| Deployment admission dry run | Passed | Deployment and Service accepted by API server |
| Kubernetes rollout | Passed | Deployment reported successfully rolled out |
| Application Pod | Passed | Pod reached `Running` and `Ready` |
| Non-root execution | Passed | Container process UID/GID `10001:10001` |
| Privilege escalation | Disabled | `allowPrivilegeEscalation: false` |
| Root filesystem | Read-only | `readOnlyRootFilesystem: true` |
| Linux capabilities | Dropped | `capabilities.drop: ["ALL"]` |
| HTTP health endpoint | Passed | Returned `status: healthy` |

## Signature rejection test: pending conclusive verification

A request using a nonexistent image tag was denied because GHCR returned
`MANIFEST_UNKNOWN`. This is not proof of signature rejection.

A request using `ghcr.io/stefanprodan/podinfo:latest` was accepted by the
Kyverno policy because that image is outside the policy's configured image
reference scope. This is not a negative signature test.

A conclusive test still needs to demonstrate that an existing image matching
the protected repository scope, but lacking a valid signature from the
trusted workflow identity, is rejected specifically by signature verification.

## Operational notes

- The trusted image was pinned to a digest during admission.
- The application is exposed through an internal ClusterIP Service.
- The successful HTTP health response confirms the endpoint is operational.
- Gatekeeper registry enforcement and Kyverno signature verification are
  separate controls and should be tested independently.
