
#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${NAMESPACE:-zero-trust-demo}"
EXPECTED_CONTEXT="kind-zero-trust"

UNSIGNED_IMAGE="${UNSIGNED_IMAGE:-ghcr.io/cloudwithnikhil/zero-trust-pipeline:unsigned-test-20261029113243}"
SIGNED_IMAGE="${SIGNED_IMAGE:-ghcr.io/cloudwithnikhil/zero-trust-pipeline:aa772d516a8238a10e589f06cb88f169e6865ff3}"

EXPECTED_DENIAL="Image must have a valid Cosign signature from the trusted GitHub Actions workflow."

PASSED=0
FAILED=0

pass() {
    printf '\033[32m[PASS]\033[0m %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf '\033[31m[FAIL]\033[0m %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '%s\n' "$2"
    fi
    FAILED=$((FAILED + 1))
}

printf '\nZero-Trust Image Admission Regression Tests\n'
printf 'Namespace: %s\n' "$NAMESPACE"

# Confirm the required tools are installed.
for tool in kubectl mktemp grep; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf '[ERROR] Required command not found: %s\n' "$tool" >&2
        exit 2
    fi
done

# Verify that tests target the intended Kind cluster.
if ! CONTEXT="$(kubectl config current-context 2>&1)"; then
    printf '[ERROR] Unable to determine the Kubernetes context:\n%s\n' "$CONTEXT" >&2
    exit 2
fi

if [[ "$CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
    printf '[ERROR] Expected context %s; current context: %s\n' \
        "$EXPECTED_CONTEXT" "$CONTEXT" >&2
    exit 2
fi

# Temporary files are automatically removed on exit.
TMP_DIR="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP_DIR"' EXIT

run_admission_dry_run() {
    local name="$1"
    local image="$2"
    local manifest="$TMP_DIR/${name}.yaml"
    local stdout_file="$TMP_DIR/${name}.stdout"
    local stderr_file="$TMP_DIR/${name}.stderr"

    cat > "$manifest" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
spec:
  containers:
    - name: test
      image: ${image}
      imagePullPolicy: Always
EOF

    # Capture both streams separately so an expected policy denial
    # can be tested without confusing it with a shell error.
    if kubectl create --dry-run=server -f "$manifest" \
        >"$stdout_file" 2>"$stderr_file"; then
        ADMISSION_EXIT_CODE=0
    else
        ADMISSION_EXIT_CODE=$?
    fi

    ADMISSION_OUTPUT="$(cat "$stdout_file" "$stderr_file")"
}

# Negative control: unsigned image must be rejected for the expected reason.
run_admission_dry_run \
    "unsigned-admission-regression" "$UNSIGNED_IMAGE"

if [[ "$ADMISSION_EXIT_CODE" -ne 0 ]] &&
   grep -Fq -- "$EXPECTED_DENIAL" <<< "$ADMISSION_OUTPUT"; then
    pass "Unsigned image denied by signature policy"
else
    fail "Unsigned image was not denied for the expected reason" \
        "kubectl exit code: $ADMISSION_EXIT_CODE
$ADMISSION_OUTPUT"
fi

# Positive control: trusted signed image must be admitted.
run_admission_dry_run \
    "signed-admission-regression" "$SIGNED_IMAGE"

if [[ "$ADMISSION_EXIT_CODE" -eq 0 ]] &&
   grep -Eqi 'server dry run' <<< "$ADMISSION_OUTPUT"; then
    pass "Trusted signed image admitted"
else
    fail "Trusted signed image was not admitted" \
        "kubectl exit code: $ADMISSION_EXIT_CODE
$ADMISSION_OUTPUT"
fi

printf '\n----------------------------------------\n'
printf 'Results: %d passed, %d failed\n' "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    printf 'Admission regression tests failed.\n' >&2
    exit 1
fi

printf 'All admission regression tests passed.\n'
