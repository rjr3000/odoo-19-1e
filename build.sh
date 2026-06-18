#!/usr/bin/env bash
# Local build: thin layer on evoluzion26/odoo-19-e1 (enterprise already in factory base).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONTEXT="$SCRIPT_DIR/build-context"
IMAGE_REPO="${ODOO_IMAGE_REPO:-evoluzion26/odoo-19-1e}"
PLATFORM="${BUILD_PLATFORM:-linux/amd64}"
BASE_IMAGE="${BASE_IMAGE:-evoluzion26/odoo-19-e1:latest}"

docker pull "$BASE_IMAGE"
docker build --platform "$PLATFORM" --build-arg BASE_IMAGE="$BASE_IMAGE" -t "${IMAGE_REPO}:latest" "$BUILD_CONTEXT"
echo "OK built ${IMAGE_REPO}:latest from ${BASE_IMAGE}"

if [[ "${PUSH:-0}" == "1" ]]; then
  docker push "${IMAGE_REPO}:latest"
  echo "OK pushed ${IMAGE_REPO}:latest"
fi
