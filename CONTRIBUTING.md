# Contributing

Thank you for your interest in contributing to Zero Trust CI/CD Pipeline.

This project demonstrates container supply-chain security and Kubernetes
admission enforcement using GitHub Actions, Docker, Grype, SPDX SBOM,
Cosign, Kyverno, OPA Gatekeeper, and Kind.

Contributions that improve security, reliability, documentation, and
reproducibility are welcome.

## Before You Start

- Read the project README and architecture documentation.
- Review the [Code of Conduct](CODE_OF_CONDUCT.md).
- Check existing issues and pull requests before opening a new one.
- For security vulnerabilities, follow [SECURITY.md](SECURITY.md) instead
  of opening a public issue.

## Development Environment

The project is developed and tested with tools including:

- Git
- Docker
- kubectl
- Helm
- Kind
- Cosign
- PowerShell on Windows or Bash on Linux/macOS

Install the tools required for the part of the project you intend to change.

## Making Changes

1. Fork the repository.
2. Create a feature branch from `main`.
3. Make a focused change.
4. Add or update tests and documentation where appropriate.
5. Run the relevant validation scripts.
6. Commit your changes and open a pull request against `main`.

Use descriptive branch names, for example:

- `feature/improve-admission-tests`
- `fix/gatekeeper-policy`
- `docs/update-installation-guide`

## Validation

Run the repository security validation script:

```powershell
.\scripts\validate-security.ps1
```

Run the image admission tests when your changes affect image verification
or Kubernetes admission:

```powershell
.\scripts\test-image-admission.ps1
```

For Gatekeeper policy or test changes, run the Gatekeeper test script in
an environment with the required Kubernetes tooling and cluster available:

```bash
bash scripts/test-gatekeeper-registry.sh
```

If a test cannot be run, explain why in your pull request. Do not claim that
a test passed unless you actually ran it.

## Security-sensitive Changes

Changes to any of the following deserve particular care:

- `.github/workflows/`
- `Dockerfile`
- `kubernetes/policies/`
- `scripts/`
- Image publishing and signing configuration
- Cosign identity and OIDC verification
- Admission policy scope and enforcement

Do not weaken security checks merely to make a workflow pass. Explain the
security impact of changes to trusted identities, permissions, image
references, policy exceptions, or admission enforcement.

Never commit secrets, private keys, access tokens, kubeconfig files, or
credentials. Use GitHub Actions secrets or OIDC-based authentication where
appropriate.

## Pull Request Guidelines

A pull request should:

- Explain the problem and proposed solution.
- Describe security implications, if any.
- Include relevant test results.
- Update documentation when behavior or setup changes.
- Keep changes focused and avoid unrelated formatting changes.
- Identify any limitations or follow-up work.

Maintainers may request changes before merging.

## License

By contributing, you agree that your contributions will be licensed under
the MIT License that covers this repository.
