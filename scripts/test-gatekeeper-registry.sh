#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="zero-trust-demo"
ALLOWED_IMAGE="${ALLOWED_IMAGE:-ghcr.io/cloudwithnikhil/zero-trust-pipeline:aa772d516a8238a10e589f06cb88f169e6865ff3}"
DENIED_IMAGE="docker.io/library/nginx:latest"

echo "Testing approved GHCR image..."
kubectl run gatekeeper-allowed-test \
  --namespace "$NAMESPACE" \
  --image="$ALLOWED_IMAGE" \
  --dry-run=server \
  -o yaml >/dev/null

echo "PASS: approved GHCR image was admitted."

echo "Testing unapproved Docker Hub image..."
if output=$(kubectl run gatekeeper-denied-test \
  --namespace "$NAMESPACE" \
  --image="$DENIED_IMAGE" \
  --dry-run=server \
  -o yaml 2>&1); then
  echo "FAIL: unapproved image was admitted."
  exit 1
fi

if [[ "$output" == *"not from an approved registry"* ]]; then
  echo "PASS: unapproved image was denied by Gatekeeper."
else
  echo "FAIL: request failed for an unexpected reason."
  echo "$output"
  exit 1
fi
