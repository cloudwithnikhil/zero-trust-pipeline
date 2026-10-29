#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="zero-trust-demo"
ALLOWED_IMAGE="${ALLOWED_IMAGE:-ghcr.io/cloudwithnikhil/zero-trust-pipeline:aa772d516a8238a10e589f06cb88f169e6865ff3}"
DENIED_IMAGE="docker.io/library/nginx:latest"
MISLEADING_IMAGE="ghcr.io.evil.example/nginx:latest"

assert_denied() {
  local test_name="$1"
  shift

  local output
  if output=$("$@" 2>&1); then
    echo "FAIL: $test_name was admitted."
    exit 1
  fi

  if [[ "$output" == *"not from an approved registry"* ]]; then
    echo "PASS: $test_name was denied by Gatekeeper."
  else
    echo "FAIL: $test_name failed for an unexpected reason."
    echo "$output"
    exit 1
  fi
}

echo "Testing approved GHCR image..."
kubectl run gatekeeper-allowed-test \
  --namespace "$NAMESPACE" \
  --image="$ALLOWED_IMAGE" \
  --dry-run=server \
  -o yaml >/dev/null
echo "PASS: approved GHCR image was admitted."

echo "Testing unapproved Docker Hub image..."
assert_denied "unapproved Docker Hub image" \
  kubectl run gatekeeper-denied-test \
    --namespace "$NAMESPACE" \
    --image="$DENIED_IMAGE" \
    --dry-run=server \
    -o yaml

echo "Testing misleading registry hostname..."
assert_denied "misleading registry hostname" \
  kubectl run gatekeeper-misleading-test \
    --namespace "$NAMESPACE" \
    --image="$MISLEADING_IMAGE" \
    --dry-run=server \
    -o yaml

echo "Testing unapproved init container image..."

INIT_TEST_FILE="$(mktemp)"
trap 'rm -f "$INIT_TEST_FILE"' EXIT

cat > "$INIT_TEST_FILE" <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: gatekeeper-init-denied-test
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  initContainers:
    - name: init-test
      image: ${DENIED_IMAGE}
  containers:
    - name: main
      image: ${ALLOWED_IMAGE}
YAML

assert_denied "unapproved init container image" \
  kubectl create --dry-run=server -f "$INIT_TEST_FILE" -o yaml
