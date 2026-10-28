
#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="zero-trust-demo"
PASSED=0
FAILED=0

pass() {
    printf '\033[32m[PASS]\033[0m %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf '\033[31m[FAIL]\033[0m %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '       %s\n' "$2"
    fi
    FAILED=$((FAILED + 1))
}

# Verify the required local tools.
for cmd in kubectl python grep; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf 'ERROR: Required command not found: %s\n' "$cmd" >&2
        exit 2
    fi
done

# Arguments: description, Python expression, then kubectl arguments.
check_json() {
    if (( $# < 3 )); then
        fail "Kubernetes JSON check" "Internal error: insufficient arguments."
        return 1
    fi

    local description="$1"
    local expression="$2"
    shift 2

    local output
    if ! output=$(kubectl "$@" -o json 2>&1); then
        fail "$description" "$output"
        return 1
    fi

    if ! printf '%s' "$output" | python -c "$expression"; then
        fail "$description" "The resource did not meet the expected condition."
        return 1
    fi

    pass "$description"
}

printf '\nZero-Trust Pipeline Security Validation\n'
printf 'Namespace: %s\n\n' "$NAMESPACE"

# 1. Kyverno ImageValidatingPolicy readiness.
check_json "Kyverno image-verification policy is Ready" \
'import json,sys; p=json.load(sys.stdin); sys.exit(0 if p.get("status",{}).get("conditionStatus",{}).get("ready") is True else 1)' \
get imagevalidatingpolicy verify-zero-trust-demo || :

# 2. Gatekeeper controller availability.
check_json "Gatekeeper controller is available" \
'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status",{}).get("availableReplicas",0) >= 1 else 1)' \
get deployment gatekeeper-controller-manager -n gatekeeper-system || :

# 3. Application Deployment availability.
check_json "Application Deployment is available" \
'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("status",{}).get("availableReplicas",0) >= 1 else 1)' \
get deployment zero-trust-demo -n "$NAMESPACE" || :

# 4. Workload hardening.
SECURITY_EXPRESSION=$(cat <<'PYTHON'
import json
import sys

d = json.load(sys.stdin)
pod = d["spec"]["template"]["spec"]
containers = pod.get("containers", [])
container = next((c for c in containers if c.get("name") == "app"), None)

checks = [
    (pod.get("securityContext", {}).get("runAsNonRoot") is True,
     "runAsNonRoot must be true"),
    (pod.get("securityContext", {}).get("runAsUser") == 10001,
     "runAsUser must be 10001"),
    (pod.get("automountServiceAccountToken") is False,
     "Service-account token automount must be disabled"),
    (container is not None, "Container app must exist"),
]

if container:
    security = container.get("securityContext", {})
    limits = container.get("resources", {}).get("limits", {})

    checks.extend([
        (security.get("readOnlyRootFilesystem") is True,
         "Root filesystem must be read-only"),
        (security.get("allowPrivilegeEscalation") is False,
         "Privilege escalation must be disabled"),
        ("ALL" in security.get("capabilities", {}).get("drop", []),
         "All Linux capabilities must be dropped"),
        (bool(limits.get("cpu")), "CPU limit must be configured"),
        (bool(limits.get("memory")), "Memory limit must be configured"),
    ])

errors = [message for passed, message in checks if not passed]

if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYTHON
)

check_json "Workload security context is hardened" \
"$SECURITY_EXPRESSION" \
get deployment zero-trust-demo -n "$NAMESPACE" || :

# 5. Application health endpoint.
HEALTH_OUTPUT=""
if HEALTH_OUTPUT=$(kubectl exec -n "$NAMESPACE" deployment/zero-trust-demo -- \
    python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=5).read().decode())" 2>&1); then

    if printf '%s' "$HEALTH_OUTPUT" | python -c '
import json,sys
try:
    response = json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if response.get("status") == "healthy" else 1)
'; then
        pass "Application health endpoint responds healthy"
    else
        fail "Application health endpoint responds healthy" \
            "Health response was invalid or not healthy: $HEALTH_OUTPUT"
    fi
else
    fail "Application health endpoint responds healthy" "$HEALTH_OUTPUT"
fi

# 6. Gatekeeper must reject an image from Docker Hub.
REGISTRY_OUTPUT=""
if REGISTRY_OUTPUT=$(kubectl run registry-policy-negative-test \
    --namespace "$NAMESPACE" \
    --image=docker.io/library/nginx:latest \
    --restart=Never \
    --dry-run=server \
    -o name 2>&1); then

    fail "Registry policy rejects Docker Hub images" \
        "An image from Docker Hub was unexpectedly admitted."
else
    if printf '%s' "$REGISTRY_OUTPUT" |
        grep -Eiq 'forbidden|denied|not allowed|violat|constraint|registry'; then
        pass "Registry policy rejects Docker Hub images"
    else
        fail "Registry policy rejects Docker Hub images" \
            "Could not confirm a registry-policy denial: $REGISTRY_OUTPUT"
    fi
fi

printf '\n----------------------------------------\n'
printf 'Results: %s passed, %s failed\n' "$PASSED" "$FAILED"

if (( FAILED > 0 )); then
    printf '\033[31mSecurity validation needs attention.\033[0m\n'
    exit 1
fi

printf '\033[32mAll security validation checks passed.\033[0m\n'
exit 0
