
param(
    [string]$Namespace = "zero-trust-demo",
    [string]$UnsignedImage = "ghcr.io/cloudwithnikhil/zero-trust-pipeline:unsigned-test-20261029113243",
    [string]$SignedImage = "ghcr.io/cloudwithnikhil/zero-trust-pipeline:aa772d516a8238a10e589f06cb88f169e6865ff3"
)

$ErrorActionPreference = "Stop"
$Passed = 0
$Failed = 0



function Invoke-AdmissionDryRun {
    param(
        [string]$Name,
        [string]$Image
    )

    $yaml = @"
apiVersion: v1
kind: Pod
metadata:
  name: $Name
  namespace: $Namespace
spec:
  containers:
    - name: test
      image: $Image
      imagePullPolicy: Always
"@

    $tempInput = [System.IO.Path]::GetTempFileName()
    $tempOutput = [System.IO.Path]::GetTempFileName()
    $tempError = [System.IO.Path]::GetTempFileName()

    try {
        [System.IO.File]::WriteAllText(
            $tempInput,
            $yaml,
            [System.Text.UTF8Encoding]::new($false)
        )

        $previousPreference = $ErrorActionPreference

        try {
            $ErrorActionPreference = "Continue"

            & kubectl create --dry-run=server -f $tempInput `
                1> $tempOutput 2> $tempError

            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }

        $stdout = Get-Content -Path $tempOutput -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -Path $tempError -Raw -ErrorAction SilentlyContinue
        $message = "$stdout`n$stderr".Trim()

        return @{
            ExitCode = $exitCode
            Output   = $message
        }
    }
    finally {
        Remove-Item $tempInput, $tempOutput, $tempError `
            -Force -ErrorAction SilentlyContinue
    }
}


Write-Host "`nZero-Trust Image Admission Regression Tests" -ForegroundColor Cyan
Write-Host "Namespace: $Namespace"

# Verify that tests run against the intended Kind cluster.
$context = & kubectl config current-context 2>&1
if ($LASTEXITCODE -ne 0 -or $context.Trim() -ne "kind-zero-trust") {
    Write-Host "[FAIL] Expected context kind-zero-trust; current context: $context" -ForegroundColor Red
    return
}

# Negative control: an unsigned image must be denied.
$result = Invoke-AdmissionDryRun `
    -Name "unsigned-admission-regression" `
    -Image $UnsignedImage

if (
    $result.ExitCode -ne 0 -and
    $result.Output -match [regex]::Escape(
        "Image must have a valid Cosign signature from the trusted GitHub Actions workflow."
    )
) {
    Write-Host "[PASS] Unsigned image denied by signature policy" -ForegroundColor Green
    $Passed++
}
else {
    Write-Host "[FAIL] Unsigned image was not denied for the expected reason" -ForegroundColor Red
    Write-Host $result.Output -ForegroundColor Yellow
    $Failed++
}

# Positive control: the trusted signed image must be admitted.
$result = Invoke-AdmissionDryRun `
    -Name "signed-admission-regression" `
    -Image $SignedImage

if (
    $result.ExitCode -eq 0 -and
    $result.Output -match "server dry run"
) {
    Write-Host "[PASS] Trusted signed image admitted" -ForegroundColor Green
    $Passed++
}
else {
    Write-Host "[FAIL] Trusted signed image was not admitted" -ForegroundColor Red
    Write-Host $result.Output -ForegroundColor Yellow
    $Failed++
}

Write-Host "`n----------------------------------------"
Write-Host "Results: $Passed passed, $Failed failed"

if ($Failed -gt 0) {
    Write-Host "Admission regression tests failed." -ForegroundColor Red
    return
}

Write-Host "All admission regression tests passed." -ForegroundColor Green
