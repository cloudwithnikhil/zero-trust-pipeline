$ErrorActionPreference = "Stop"
$Namespace = "zero-trust-demo"
$Passed = 0
$Failed = 0

function Test-Check {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        & $Action
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    }
    catch {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow
        $script:Failed++
    }
}

function Get-KubectlJson {
    param([string[]]$Arguments)

    $output = & kubectl @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join "`n")
    }

    return (($output -join "`n") | ConvertFrom-Json)
}

Write-Host "`nZero-Trust Pipeline Security Validation" -ForegroundColor Cyan
Write-Host "Namespace: $Namespace`n"

# 1. Kyverno policy must exist and be ready.
Test-Check "Kyverno image-verification policy is Ready" {
    $policy = Get-KubectlJson @(
        "get", "imagevalidatingpolicy",
        "verify-zero-trust-demo", "-o", "json"
    )

    $ready = $policy.status.conditionStatus.ready

    if ($ready -ne $true) {
        throw "The policy does not report conditionStatus.ready=true."
    }
}

# 2. Gatekeeper controller must be available.
Test-Check "Gatekeeper controller is available" {
    $deployment = Get-KubectlJson @(
        "get", "deployment", "gatekeeper-controller-manager",
        "-n", "gatekeeper-system", "-o", "json"
    )

    if ($deployment.status.availableReplicas -lt 1) {
        throw "No available Gatekeeper controller replicas."
    }
}

# 3. Application deployment must have an available replica.
Test-Check "Application Deployment is available" {
    $deployment = Get-KubectlJson @(
        "get", "deployment", "zero-trust-demo",
        "-n", $Namespace, "-o", "json"
    )

    if ($deployment.status.availableReplicas -lt 1) {
        throw "Application has no available replicas."
    }
}

# 4. Verify pod-level hardening.
Test-Check "Workload security context is hardened" {
    $deployment = Get-KubectlJson @(
        "get", "deployment", "zero-trust-demo",
        "-n", $Namespace, "-o", "json"
    )

    $podSpec = $deployment.spec.template.spec
    $container = $podSpec.containers |
        Where-Object { $_.name -eq "app" } |
        Select-Object -First 1

    if (-not $container) {
        throw "Container 'app' was not found."
    }

    if ($podSpec.securityContext.runAsNonRoot -ne $true) {
        throw "runAsNonRoot is not true."
    }

    if ($podSpec.securityContext.runAsUser -ne 10001) {
        throw "Expected runAsUser 10001."
    }

    if ($podSpec.automountServiceAccountToken -ne $false) {
        throw "Service-account token automount is not disabled."
    }

    if ($container.securityContext.readOnlyRootFilesystem -ne $true) {
        throw "Root filesystem is not read-only."
    }

    if ($container.securityContext.allowPrivilegeEscalation -ne $false) {
        throw "Privilege escalation is not disabled."
    }

    if (@($container.securityContext.capabilities.drop) -notcontains "ALL") {
        throw "Linux capabilities ALL are not dropped."
    }

    if (-not $container.resources.limits.cpu -or
        -not $container.resources.limits.memory) {
        throw "CPU or memory limits are missing."
    }
}

# 5. Health endpoint must return valid JSON with healthy status.
Test-Check "Application health endpoint responds healthy" {
    $output = & kubectl exec -n $Namespace deployment/zero-trust-demo -- `
        python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=5).read().decode())" 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw ($output -join "`n")
    }

    $response = ($output -join "`n") | ConvertFrom-Json

    if ($response.status -ne "healthy") {
        throw "Health endpoint did not return status=healthy."
    }
}

# 6. A Docker Hub image must be rejected by the registry policy.
Test-Check "Registry policy rejects Docker Hub images" {
    $previousPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = "Continue"

        $output = & kubectl run registry-policy-negative-test `
            --namespace $Namespace `
            --image=docker.io/library/nginx:latest `
            --restart=Never `
            --dry-run=server `
            -o name 2>&1

        $exitCode = $LASTEXITCODE
        $message = $output | Out-String
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($exitCode -eq 0) {
        throw "An image from Docker Hub was unexpectedly admitted."
    }

    if ($message -notmatch '(?i)forbidden|denied|not allowed|violat|constraint|registry') {
        throw "The request failed, but the output did not clearly identify a registry-policy denial: $message"
    }
}


# 7. An unsigned image must be rejected by the Cosign signature policy.
Test-Check "Admission policy rejects unsigned images" {
    $unsignedImage = "ghcr.io/cloudwithnikhil/zero-trust-pipeline:unsigned-test-20261029113243"

    $yaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-admission-validation
  namespace: $Namespace
spec:
  containers:
    - name: test
      image: $unsignedImage
      imagePullPolicy: Always
"@

    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllText(
            $tempFile,
            $yaml,
            [System.Text.UTF8Encoding]::new($false)
        )

        $previousPreference = $ErrorActionPreference

        try {
            $ErrorActionPreference = "Continue"
            $output = & kubectl create --dry-run=server -f $tempFile 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }

        $message = $output | Out-String

        if ($exitCode -eq 0) {
            throw "Unsigned image was unexpectedly admitted."
        }

        if ($message -notmatch [regex]::Escape(
            "Image must have a valid Cosign signature from the trusted GitHub Actions workflow."
        )) {
            throw "Request failed for a reason other than the expected signature-policy denial: $message"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# 8. The trusted signed image must be admitted.
Test-Check "Admission policy accepts trusted signed images" {
    $signedImage = "ghcr.io/cloudwithnikhil/zero-trust-pipeline:aa772d516a8238a10e589f06cb88f169e6865ff3"

    $yaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: signed-admission-validation
  namespace: $Namespace
spec:
  containers:
    - name: test
      image: $signedImage
      imagePullPolicy: Always
"@

    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllText(
            $tempFile,
            $yaml,
            [System.Text.UTF8Encoding]::new($false)
        )

        $output = & kubectl create --dry-run=server -f $tempFile 2>&1
        $exitCode = $LASTEXITCODE
        $message = $output | Out-String

        if ($exitCode -ne 0) {
            throw "Trusted signed image was not admitted: $message"
        }

        if ($message -notmatch '(?i)server dry run') {
            throw "kubectl did not confirm server-side dry-run admission: $message"
        }
    }
    finally {
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
}


Write-Host "`n----------------------------------------"
Write-Host "Results: $Passed passed, $Failed failed"

if ($Failed -gt 0) {
    Write-Host "Security validation needs attention." -ForegroundColor Red
    exit 1
}

Write-Host "All security validation checks passed." -ForegroundColor Green
exit 0
