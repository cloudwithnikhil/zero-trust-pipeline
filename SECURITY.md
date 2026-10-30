# Security Policy

## Supported Versions

Security fixes are applied to the latest code on the `main` branch.

Older commits, forks, and unmaintained copies may not receive security fixes.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues,
discussions, or pull requests.

Use GitHub's private vulnerability reporting feature:

https://github.com/cloudwithnikhil/zero-trust-pipeline/security/advisories/new

If private vulnerability reporting is unavailable, contact the repository
maintainer privately through GitHub before disclosing the issue publicly.

When reporting a vulnerability, include:

- A description of the affected component.
- The potential security impact.
- Steps to reproduce the issue.
- Relevant logs, screenshots, or proof of concept, if safe to share.
- A suggested mitigation, if known.

Do not include live credentials, private keys, personal information, or
production secrets in a report.

## Response Process

The maintainer will review the report, assess its impact, and work with the
reporter on an appropriate remediation.

Please allow reasonable time for investigation and a fix before public
disclosure.

## Scope

Examples of security-sensitive areas include:

- GitHub Actions workflow permissions and untrusted inputs.
- Container build and publishing processes.
- Cosign image signing and identity verification.
- SBOM generation and vulnerability scanning.
- Kyverno and Gatekeeper admission policies.
- Kubernetes workload security configuration.

This project is an educational and demonstration project. Its presence in
this repository does not constitute a guarantee that it is suitable for
production deployment without independent review and adaptation.
