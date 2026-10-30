<div align="center">

# 🛡️ Zero-Trust CI/CD Pipeline

**Secure container delivery where nothing is trusted by default — every image is scanned, inventoried, signed, and verified again before it is allowed to run.**

[![CI/CD](https://github.com/cloudwithnikhil/zero-trust-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/cloudwithnikhil/zero-trust-pipeline/actions/workflows/ci.yml)
![GitHub Actions](https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker&logoColor=white)
![Cosign](https://img.shields.io/badge/Signing-Cosign%20(keyless)-5A67D8)
![Kubernetes](https://img.shields.io/badge/Runtime-Kubernetes%20(Kind)-326CE5?logo=kubernetes&logoColor=white)
![Kyverno](https://img.shields.io/badge/Admission-Kyverno-F77B3D)
![Gatekeeper](https://img.shields.io/badge/Policy-OPA%20Gatekeeper-7D64FF)
![SBOM](https://img.shields.io/badge/SBOM-SPDX-4CAF50)

**[📐 Architecture](docs/architecture.md)** · **[✅ Security Validation](docs/security-validation.md)** · **[🎬 Interactive Demo](https://cloudwithnikhil.github.io/zero-trust-pipeline/zero-trust-ci-cd-pipeline-architecture.html)**

</div>

<p align="center">
  <img src="docs/zero-trust-ci-cd-cover.png" alt="Zero Trust CI/CD Pipeline Architecture" width="100%" />
</p>

---

## Table of Contents

1. [Overview](#1-overview)
2. [Why Zero Trust for CI/CD?](#2-why-zero-trust-for-cicd)
3. [Architecture](#3-architecture)
4. [Technology Stack](#4-technology-stack)
5. [Repository Structure](#5-repository-structure)
6. [The Application and Container Image](#6-the-application-and-container-image)
7. [CI Pipeline (GitHub Actions)](#7-ci-pipeline-github-actions)
8. [Image Signing and Verification](#8-image-signing-and-verification)
9. [Kubernetes Admission Control](#9-kubernetes-admission-control)
10. [Workload Hardening](#10-workload-hardening)
11. [Threat Model: What Each Control Stops](#11-threat-model-what-each-control-stops)
12. [Getting Started](#12-getting-started)
13. [Security Validation and Test Results](#13-security-validation-and-test-results)
14. [Design Decisions and Known Limitations](#14-design-decisions-and-known-limitations)
15. [Roadmap](#15-roadmap)
16. [Glossary](#16-glossary)
17. [Documentation and References](#17-documentation-and-references)

---

## 1. Overview

This project is a **DevSecOps portfolio project** that demonstrates an end-to-end *secure software supply chain* for a containerized application.

It answers one question: **"How do we guarantee that only code we built, scanned, and signed can run in our cluster?"**

The pipeline:

1. **Builds** a hardened container image from a small Python service.
2. **Scans** it for known vulnerabilities and **fails the build** on high-severity findings.
3. **Generates an SBOM** (Software Bill of Materials) in SPDX format.
4. **Publishes** the image to GitHub Container Registry (GHCR).
5. **Signs** the image by immutable digest with Cosign using GitHub's OIDC identity (no long-lived signing keys).
6. **Enforces** the result inside Kubernetes: Kyverno verifies the signature, Gatekeeper restricts the registry, and the workload itself runs with a locked-down security context.
7. **Tests the policies automatically** in disposable Kind clusters in CI, so signed, unsigned, and unapproved-registry scenarios are checked on every run.

> **Where to go next:** the design is explained in [`docs/architecture.md`](docs/architecture.md), and the recorded test evidence is in [`docs/security-validation.md`](docs/security-validation.md). See [section 17](#17-documentation-and-references) for the full list of references.

## 2. Why Zero Trust for CI/CD?

Traditional pipelines trust whatever lands in a registry. If an attacker pushes a tampered image, or an engineer deploys an image from an untrusted source, the cluster runs it.

Zero Trust replaces *implicit* trust with *continuous verification*:

| Principle | How it is applied here |
|---|---|
| **Never trust, always verify** | The cluster re-verifies the image signature at admission, even though CI already signed it |
| **Verify identity, not location** | Trust is tied to a specific workflow identity (`ci.yml` on `main`), not to "an image in our registry" |
| **No long-lived secrets** | Keyless signing via GitHub Actions OIDC; there is no private signing key to steal |
| **Least privilege** | Non-root, read-only filesystem, no capabilities, no service-account token |
| **Defense in depth** | Independent controls: scan → sign → registry policy → signature policy → hardened runtime |
| **Evidence over assumption** | Scan reports, SBOM, and signing evidence are produced as artifacts for every run |

## 3. Architecture

> 📐 For the full architecture write-up, see **[`docs/architecture.md`](docs/architecture.md)**. This section gives the overview.

### 3.1 Interactive architecture

![Zero Trust CI/CD Pipeline Architecture](docs/zero-trust-ci-cd-pipeline.svg)

**[▶ View the Interactive Architecture](https://cloudwithnikhil.github.io/zero-trust-pipeline/zero-trust-ci-cd-pipeline-architecture.html)**

The animation follows a container image through build validation, vulnerability scanning, SBOM generation, image signing, and Kubernetes admission control. It includes three scenarios:

- **Signed image:** the intended successful signature-verification and admission flow.
- **Unsigned image:** how the signature policy is intended to reject an unsigned image.
- **Unapproved registry:** how Gatekeeper is intended to reject an image from an unapproved registry.

The animation is an architectural demonstration. Actual enforcement behavior is determined by the GitHub Actions workflow and the Kubernetes policy manifests in this repository.

### 3.2 High-level flow

```mermaid
flowchart TD
    DEV[Developer] -->|git push| GH[GitHub Repository]
    GH --> GHA[GitHub Actions Workflow<br/>ci.yml]

    subgraph J1["Job 1: validate"]
        B[Docker Build] --> S[Grype Vulnerability Scan<br/>fail on severity ≥ high]
        S --> SB[SPDX SBOM Generation]
    end

    subgraph J2["Job 2: publish-and-sign (main only)"]
        P[Push image to GHCR] --> SIGN[Cosign keyless signing<br/>by immutable digest]
        SIGN --> VER[Cosign verify<br/>identity + OIDC issuer]
    end

    GHA --> J1 --> J2
    J2 --> REG[(GHCR<br/>Signed Image)]

    subgraph J3["Job 3: admission-test (disposable Kind)"]
        KT[Install Kyverno via Helm<br/>apply signature policy] --> KR[Signed: accepted<br/>Unsigned: rejected]
    end

    subgraph J4["Job 4: gatekeeper-test (disposable Kind)"]
        GT[Install Gatekeeper<br/>apply template + constraint] --> GR[Approved registry: allowed<br/>Unapproved / misleading / init: denied]
    end

    VER --> J3
    VER --> J4

    REG -->|image pull request| K8S

    subgraph K8S["Kubernetes Cluster (Kind)"]
        API[API Server] --> ADM{Admission Control}
        ADM --> KYV[Kyverno<br/>Verify Cosign signature]
        ADM --> GK[OPA Gatekeeper<br/>Allow GHCR only]
        KYV --> OK[Pod admitted]
        GK --> OK
    end

    KYV -.->|unsigned / wrong identity| DENY[Request denied]
    GK -.->|other registry| DENY
```

> The diagram shows the automated pipeline and the admission-policy tests. The repository does **not** implement a production release process that deploys every verified image to a production cluster.

### 3.3 Trust chain (sequence)

```mermaid
sequenceDiagram
    autonumber
    participant Dev as Developer
    participant GH as GitHub Actions
    participant OIDC as GitHub OIDC Provider
    participant Reg as GHCR
    participant K as Kubernetes API
    participant Kyv as Kyverno
    participant Gk as Gatekeeper

    Dev->>GH: Push to main
    GH->>GH: Build, scan (Grype), generate SBOM
    GH->>Reg: Push image (get digest)
    GH->>OIDC: Request short-lived identity token
    OIDC-->>GH: OIDC token (workflow identity)
    GH->>Reg: Cosign sign by digest (keyless)
    GH->>Reg: Cosign verify (identity + issuer)

    Dev->>K: Deploy workload (image pinned by digest)
    K->>Gk: Is registry allowed?
    Gk-->>K: Allow (ghcr.io) / Deny (e.g. docker.io)
    K->>Kyv: Is image signed by trusted workflow?
    Kyv->>Reg: Fetch signature + verify identity/issuer
    Kyv-->>K: Allow / Deny
    K-->>Dev: Pod admitted or request rejected
```

### 3.4 Defense layers

```
┌──────────────────────────────────────────────────────────────┐
│ Layer 1  SOURCE & BUILD   Hardened Dockerfile, non-root user │
├──────────────────────────────────────────────────────────────┤
│ Layer 2  SCAN & INVENTORY Grype scan (fails build) + SBOM    │
├──────────────────────────────────────────────────────────────┤
│ Layer 3  PROVENANCE       Cosign keyless signature by digest │
├──────────────────────────────────────────────────────────────┤
│ Layer 4  REGISTRY POLICY  Gatekeeper: GHCR only              │
├──────────────────────────────────────────────────────────────┤
│ Layer 5  SIGNATURE POLICY Kyverno: trusted workflow identity │
├──────────────────────────────────────────────────────────────┤
│ Layer 6  RUNTIME          Restricted security context        │
└──────────────────────────────────────────────────────────────┘
```

## 4. Technology Stack

| Area | Tool | Role in this project |
|---|---|---|
| CI/CD | **GitHub Actions** | Orchestrates build, scan, SBOM, publish, sign, and policy tests |
| Containerization | **Docker** | Builds the application image |
| Base image | **python:3.12-alpine** | Small attack surface |
| Vulnerability scanning | **Grype** | Scans the image; JSON report; fails the build at `high` severity |
| SBOM | **SPDX (JSON)** | Machine-readable inventory of image components |
| Registry | **GHCR** | Stores published images |
| Signing | **Cosign (keyless / Sigstore)** | Signs by digest using GitHub OIDC identity |
| Cluster | **Kubernetes (Kind)** | Local cluster `kind-zero-trust` plus disposable clusters in CI |
| Signature enforcement | **Kyverno** (`ImageValidatingPolicy`) | Rejects images without a valid signature from the trusted workflow |
| Registry enforcement | **OPA Gatekeeper** | Rejects images from non-approved registries |
| Packaging | **Helm** | Installs Kyverno and Gatekeeper in test clusters |
| Validation | **PowerShell and Bash** | Automated security validation and regression tests |

## 5. Repository Structure

```
zero-trust-pipeline/
├── .github/
│   └── workflows/
│       └── ci.yml                               # Four-job CI/CD workflow
├── app/
│   └── server.py                                # Demo HTTP service (/health)
├── docs/
│   ├── architecture.md                          # Architecture documentation
│   ├── security-validation.md                   # Recorded validation evidence
│   ├── zero-trust-ci-cd-cover.png               # README cover image
│   └── zero-trust-ci-cd-pipeline.svg            # Architecture diagram
├── kubernetes/
│   ├── app-deployment.yaml                      # Hardened application Deployment
│   └── policies/
│       ├── gatekeeper-constraint-template.yaml  # Reusable registry-policy logic
│       ├── gatekeeper-allowed-registry.yaml     # Constraint with the allowlist
│       └── verify-signed-images.yaml            # Kyverno signature policy
├── scripts/
│   ├── validate-security.ps1 / .sh              # Full local validation
│   ├── test-image-admission.ps1 / .sh           # Signed/unsigned admission tests
│   └── test-gatekeeper-registry.sh              # Registry policy regression tests
├── Dockerfile                                   # Hardened, non-root image definition
├── .dockerignore                                # Keeps build context minimal
├── .gitignore                                   # Excludes local evidence (artifacts/) etc.
└── README.md
```

| Path | Purpose |
|---|---|
| `.github/workflows/` | Defines the four-job pipeline: validate, publish and sign, Kyverno admission test, Gatekeeper registry test |
| `app/` | The small Python HTTP service used as the deployable workload |
| `kubernetes/` | The demo workload and the Kyverno/Gatekeeper policies |
| `scripts/` | Repeatable checks that prove the policies actually block bad images |
| `docs/` | [Architecture](docs/architecture.md), [security validation evidence](docs/security-validation.md), and README visuals |

## 6. The Application and Container Image

The application is a minimal Python service (`app/server.py`) listening on port **8080** and exposing a **`/health`** endpoint that returns `status: healthy`. It exists to give the pipeline something real to build, sign, and deploy.

### Dockerfile highlights

```dockerfile
FROM python:3.12-alpine3.24

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

RUN addgroup -S -g 10001 appgroup \
 && adduser -S -D -H -u 10001 -G appgroup appuser

WORKDIR /app
COPY --chown=10001:10001 app/server.py ./server.py

USER 10001:10001
EXPOSE 8080
CMD ["python", "server.py"]
```

| Choice | Reason |
|---|---|
| Alpine base, pinned version | Small image, fewer packages to be vulnerable, reproducible builds |
| Dedicated user/group with fixed numeric UID/GID `10001` | Runs as non-root; a numeric ID lets Kubernetes verify `runAsNonRoot` |
| No home directory, no login shell for the user | Minimises what a compromised process can use |
| Only `server.py` is copied | No build tooling, source tree, or secrets in the final image |
| `PYTHONDONTWRITEBYTECODE=1` | No `.pyc` writes, which suits a read-only root filesystem |
| `PYTHONUNBUFFERED=1` | Logs appear immediately in `docker logs` / `kubectl logs` |

## 7. CI Pipeline (GitHub Actions)

The workflow (`.github/workflows/ci.yml`, named **Zero-Trust CI/CD**) has four jobs.

### Job 1 — `validate`: Build, Scan and Generate SBOM

1. Build the container image.
2. Scan it with **Grype** (`severity-cutoff: high`, `fail-build: true`). A finding at or above the cutoff **fails the pipeline**, so a vulnerable image never reaches the registry.
3. Generate an **SPDX JSON SBOM** listing every component in the image.
4. Write build, SBOM, and scan outcomes to the **GitHub job summary**.

### Job 2 — `publish-and-sign`: Publish to GHCR and Sign with Cosign

Runs on **pushes to `main`** after Job 1 passes.

1. Publish the validated image to **GHCR**.
2. Sign it with **Cosign** using the immutable **digest** (not a mutable tag).
3. **Verify** the signature against the expected workflow identity and OIDC issuer.

### Job 3 — `admission-test`: Kyverno signature policy

1. Create an isolated **Kind** cluster.
2. Install **Kyverno** with Helm and wait for the admission components and webhook endpoints to be ready.
3. Apply the signature policy, with bounded retries for transient connectivity errors.
4. Test signed and unsigned image behavior.
5. Print diagnostics if setup or policy application fails.

### Job 4 — `gatekeeper-test`: Registry allowlist

1. Create a separate disposable **Kind** cluster.
2. Install **Gatekeeper** and apply the constraint template and constraint.
3. Run `scripts/test-gatekeeper-registry.sh` against approved and prohibited image references.

> The CI tests validate policy **behavior** in disposable clusters. They do not prove the same policies are deployed to every cluster where the application might run.

### Workflow artifacts

| Artifact | Purpose |
|---|---|
| `security-evidence` | Grype JSON vulnerability report |
| `zero-trust-demo-sbom` | SPDX JSON SBOM |
| `validated-container-image` | The image that passed validation |
| `image-signing-evidence` | Cosign signing and verification evidence |

> **Tip:** After a run, open the job summary for a quick overview and download the artifacts from the **Actions** tab for the full reports.

## 8. Image Signing and Verification

Signing is **keyless** (Sigstore). Instead of storing a private key as a secret, the workflow asks GitHub's OIDC provider for a short-lived identity token that proves *"this signature was produced by this workflow in this repository."*

| Property | Value |
|---|---|
| Expected signer identity | `https://github.com/cloudwithnikhil/zero-trust-pipeline/.github/workflows/ci.yml@refs/heads/main` |
| Expected OIDC issuer | `https://token.actions.githubusercontent.com` |
| What is signed | The image **digest** (immutable) |

**Why this matters**

- There is **no signing key to leak** or rotate.
- A signature from any *other* workflow, branch, or repository is rejected, even if it is technically valid. Finding *a* signature is not enough; identity and issuer must match.
- Signing by digest prevents "tag swap" attacks, where a tag is silently repointed to different content.

## 9. Kubernetes Admission Control

Two independent controllers decide whether a Pod may start. They are deliberately separate so that a failure or bypass of one does not disable the other.

### 9.1 Kyverno — signature verification

Policy file: `kubernetes/policies/verify-signed-images.yaml`

| Item | Value |
|---|---|
| Resource | `ImageValidatingPolicy` |
| Policy name | `verify-zero-trust-demo` |
| Verifies | Cosign signature, signer identity, and OIDC issuer (see section 8) |
| Denial message | `Image must have a valid Cosign signature from the trusted GitHub Actions workflow.` |

An image within the protected repository scope that is unsigned, or signed by the wrong identity, is rejected.

### 9.2 OPA Gatekeeper — registry allow-list

Policy files: `kubernetes/policies/gatekeeper-constraint-template.yaml` and `gatekeeper-allowed-registry.yaml`

| Item | Value |
|---|---|
| Constraint name | `allow-ghcr-only` |
| Behavior | Rejects any image not pulled from GHCR |
| Parameterized by | `input.parameters.registries` (at least one entry required) |
| Verified by | Denial of `docker.io/library/nginx:latest` |

The template parses the real registry hostname instead of matching substrings, and checks application **and init** containers. `scripts/test-gatekeeper-registry.sh` covers four cases:

| Scenario | Expected result |
|---|---|
| Approved GHCR image | Allowed |
| Unapproved Docker Hub image | Denied |
| Misleading registry hostname | Denied |
| Unapproved init-container image | Denied |

### 9.3 Why both?

A registry allowlist limits **where** images come from but does not prove **who built** them. A signature policy proves the builder's identity. Each closes a gap the other leaves open.

### 9.4 Environment (local validation cluster)

| Item | Value |
|---|---|
| Kubernetes context | `kind-zero-trust` |
| Namespace | `zero-trust-demo` |
| Service exposure | Internal `ClusterIP` only |
| Image reference | Pinned to an immutable digest |

## 10. Workload Hardening

The application Deployment (`kubernetes/app-deployment.yaml`) is configured to follow Kubernetes security best practice:

| Setting | Effect |
|---|---|
| Run as non-root | A compromised process does not run as root |
| Read-only root filesystem | Attackers cannot modify binaries or drop files on disk |
| Privilege escalation disabled | Blocks `setuid`-style escalation |
| All Linux capabilities dropped | Minimal kernel privileges |
| Service-account token automount disabled | No Kubernetes API credentials inside the Pod |
| CPU and memory limits | Limits resource-exhaustion impact |
| `ClusterIP` Service | Not exposed outside the cluster |

## 11. Threat Model: What Each Control Stops

| Threat | Control that mitigates it |
|---|---|
| Image contains a known high-severity vulnerability | Grype scan fails the build |
| Unknown or undocumented dependencies in the image | SPDX SBOM for every build |
| Attacker pushes a tampered image to the registry | Kyverno rejects it: no valid signature |
| Someone signs an image with a different identity or repo | Kyverno checks signer identity and issuer |
| Mutable tag is repointed to malicious content | Signing and admission use the immutable digest |
| Engineer deploys an image from a public or untrusted registry | Gatekeeper `allow-ghcr-only` |
| Registry-name trick (misleading hostname) | Hostname-aware parsing, regression-tested |
| Unapproved image hidden in an init container | Policy covers init containers, regression-tested |
| Signing key is stolen | No long-lived key exists (keyless / OIDC) |
| Container compromise leads to host or cluster pivot | Non-root, read-only FS, no capabilities, no token, resource limits |
| Compromised Pod is reachable from outside | `ClusterIP`-only Service |

## 12. Getting Started

### Prerequisites

- Docker
- [Kind](https://kind.sigs.k8s.io/), `kubectl`, and Helm
- PowerShell (`.ps1` scripts) or Bash (`.sh` scripts)
- Kyverno and OPA Gatekeeper installed in the cluster
- Cosign (optional, for manual signature verification)
- A GitHub repository with Actions and GHCR packages enabled (to reproduce the CI side)

### Run the application locally

```bash
docker build -t zero-trust-demo .
docker run --rm -p 8080:8080 zero-trust-demo

curl http://localhost:8080/health
```

### Prepare the cluster

```bash
# Create the local cluster (context becomes kind-zero-trust)
kind create cluster --name zero-trust

# Install Kyverno and Gatekeeper using their official install guides,
# then apply the manifests in the kubernetes/ directory.
```

> Apply order matters: install the Kyverno and Gatekeeper controllers first, create the Gatekeeper constraint template before its constraint, then deploy the workload.

### Verify a published image yourself

```bash
cosign verify ghcr.io/cloudwithnikhil/zero-trust-pipeline@<digest> \
  --certificate-identity "https://github.com/cloudwithnikhil/zero-trust-pipeline/.github/workflows/ci.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## 13. Security Validation and Test Results

> ✅ The full evidence record, environment details, and negative-test observations are in **[`docs/security-validation.md`](docs/security-validation.md)**.

### Run the tests

From the repository root:

```powershell
# Full validation suite
.\scripts\validate-security.ps1

# Focused image-admission regression tests
.\scripts\test-image-admission.ps1
```

```bash
# Bash equivalents
bash scripts/validate-security.sh
bash scripts/test-image-admission.sh

# Gatekeeper registry policy regression tests
bash scripts/test-gatekeeper-registry.sh
```

- The local scripts require the intended Kind cluster and admission controllers.
- The admission regression script confirms the active context is `kind-zero-trust` before running.
- Admission tests use `kubectl create --dry-run=server`, so **no persistent test Pods are created**.
- Read each script before pointing it at a shared cluster; applying a constraint can affect future deployments.

### Latest result: 8 passed, 0 failed

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Kyverno image-verification policy | ✅ Passed | `conditionStatus.ready: true` |
| 2 | Gatekeeper controller | ✅ Passed | Controller Deployment has an available replica |
| 3 | Application Deployment | ✅ Passed | At least one available replica |
| 4 | Workload security context | ✅ Passed | Non-root, read-only FS, no privilege escalation, capabilities dropped, token automount off, limits set |
| 5 | Health endpoint | ✅ Passed | `/health` returned `status: healthy` |
| 6 | Registry restriction | ✅ Passed | Gatekeeper denied `docker.io/library/nginx:latest` |
| 7 | Unsigned image admission | ✅ Rejected as expected | Kyverno denied an unsigned image in the protected repository scope |
| 8 | Trusted signed image admission | ✅ Accepted as expected | Admitted during a server-side dry run |

### Negative-test notes (what was and was not proven)

| Observation | What it means |
|---|---|
| Unsigned image from the protected repo was denied with the signature-policy message | **Valid** proof of signature enforcement |
| Image signed under an intentionally wrong identity was denied | **Valid** proof that signer identity is checked (temporary policy removed afterwards) |
| A nonexistent tag was denied (`MANIFEST_UNKNOWN`) | **Not** proof of signature enforcement; the registry simply had no such image |
| An image outside Kyverno's configured scope was accepted | Expected; it did not test signature rejection |

### Quick troubleshooting

| Symptom | First checks |
|---|---|
| Kyverno webhook connection refused | `kubectl get pods -A`, `kubectl get endpoints -A`, `kubectl get events -A --sort-by=.lastTimestamp`. This is a readiness problem, not a policy decision |
| Signed image rejected | Compare signer identity and issuer in `ci.yml` with the Kyverno policy; read the specific error instead of weakening the policy |
| Gatekeeper allows an unapproved image | Treat as a policy regression: check init-container coverage, hostname parsing, and that the constraint is enforced |
| `kubectl` cannot reach the cluster | `kubectl config current-context`, `kubectl get nodes` |

## 14. Design Decisions and Known Limitations

**Design decisions**

- **Two controllers, not one.** Kyverno (signature) and Gatekeeper (registry) cover different questions and are tested independently.
- **Digest pinning.** Digests cannot be silently repointed, unlike tags.
- **Keyless signing.** Removes key management and ties trust to a workflow identity.
- **Fail closed on scan results.** A high-severity finding stops the release.
- **Dry-run admission tests.** Prove policy behavior without leaving test workloads behind.
- **Disposable test clusters in CI.** Policy tests that intentionally reject workloads are isolated from long-lived environments.
- **Classify failures correctly.** A vulnerability finding, signature rejection, policy violation, webhook timeout, and missing dependency each need a different fix.

**Limitations**

- CI tests run in **disposable Kind clusters**; the local `kind-zero-trust` validation is a **separate** environment and must be re-run independently.
- Automated validation checks current cluster state and does not replace reviewing policy definitions, scan findings, and signing evidence.
- Local `artifacts/` evidence is excluded from Git; publish only sanitized evidence on purpose.
- No production deployment stage, runtime threat detection, alert routing, or comprehensive secret/IaC scanning is implemented.
- Scope is a single demo workload and a single namespace.

## 15. Roadmap

- [ ] Attach and verify SBOM and provenance attestations (SLSA) at admission
- [ ] Add secret scanning, IaC scanning, and static analysis stages
- [ ] Add a GitOps deployment flow (e.g., Argo CD or Flux) with environment approvals
- [ ] Add runtime threat detection (e.g., Falco)
- [ ] Add Pod Security Admission and NetworkPolicies
- [ ] Improve reporting for admission denials and webhook health
- [ ] Add a repository `LICENSE`

## 16. Glossary

| Term | Meaning |
|---|---|
| **Zero Trust** | Security model with no implicit trust; every request or artifact is verified |
| **SBOM** | Software Bill of Materials: an inventory of all components in a build |
| **SPDX** | An open, standard SBOM format |
| **Grype** | Open-source vulnerability scanner for container images and filesystems |
| **Cosign / Sigstore** | Tooling for signing and verifying container images |
| **Keyless signing** | Signing with a short-lived identity certificate from OIDC instead of a stored private key |
| **OIDC** | OpenID Connect; GitHub Actions uses it to prove a workflow's identity |
| **Digest** | Immutable content hash of an image (`sha256:...`) |
| **GHCR** | GitHub Container Registry |
| **Kyverno** | Kubernetes-native policy engine; here it verifies image signatures |
| **OPA Gatekeeper** | Policy controller for Kubernetes admission using Open Policy Agent |
| **Admission control** | Kubernetes checks that approve or reject resources before they are stored and run |
| **Kind** | "Kubernetes in Docker"; local and disposable clusters for testing |
| **Helm** | Kubernetes package manager, used here to install policy controllers |

## 17. Documentation and References

### Project documentation

| Document | What it covers |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Architecture of the pipeline: components, trust boundaries, and how an image flows from commit to cluster |
| [`docs/security-validation.md`](docs/security-validation.md) | Validation environment, the 8-check result table, and negative-test observations |
| [Interactive architecture](https://cloudwithnikhil.github.io/zero-trust-pipeline/zero-trust-ci-cd-pipeline-architecture.html) | Animated walkthrough of the signed, unsigned, and unapproved-registry scenarios |
| [`.github/workflows/ci.yml`](.github/workflows/ci.yml) | The four-job Zero-Trust CI/CD workflow |
| [`kubernetes/policies/`](kubernetes/policies) | Kyverno signature policy and Gatekeeper template and constraint |
| [`scripts/`](scripts) | Validation and regression test scripts (PowerShell and Bash) |

### Which document answers which question?

| If you want to know... | Read |
|---|---|
| How the pieces fit together and why | [Architecture](docs/architecture.md) and [section 3](#3-architecture) |
| What was tested and what the results were | [Security Validation](docs/security-validation.md) and [section 13](#13-security-validation-and-test-results) |
| How signing and verification are configured | [Section 8](#8-image-signing-and-verification) and `ci.yml` |
| How admission policies behave | [Section 9](#9-kubernetes-admission-control) and `kubernetes/policies/` |
| How to run the tests yourself | [Section 13](#13-security-validation-and-test-results) and `scripts/` |

### External references

- [Sigstore Cosign](https://docs.sigstore.dev/cosign/overview/)
- [Kyverno documentation](https://kyverno.io/docs/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/website/)
- [Grype](https://github.com/anchore/grype)
- [SPDX specification](https://spdx.dev/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Kind](https://kind.sigs.k8s.io/)

---

<div align="center">

**Author:** [cloudwithnikhil](https://github.com/cloudwithnikhil)

</div>