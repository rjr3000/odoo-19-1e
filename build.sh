#!/usr/bin/env bash
# Build odoo-19-1e (Odoo 19.0 + baked enterprise; mimics odoo-19-app-1 factory image).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_CONTEXT="$SCRIPT_DIR/build-context"
IMAGE_REPO="${ODOO_IMAGE_REPO:-evoluzion26/odoo-19-1e}"
PLATFORM="${BUILD_PLATFORM:-linux/amd64}"

resolve_enterprise_zip() {
  if [[ -n "${ENTERPRISE_ZIP_SRC:-}" && -f "${ENTERPRISE_ZIP_SRC}" ]]; then
    echo "${ENTERPRISE_ZIP_SRC}"
    return 0
  fi
  local candidate
  for candidate in \
    "$SCRIPT_DIR/addons-enterprise/enterprise-addons.zip" \
    "$SCRIPT_DIR/../odoo-19-d2/addons-enterprise/enterprise-addons.zip" \
    "$SCRIPT_DIR/../odoo-19-all/addons-enterprise/enterprise-addons.zip" \
    "$SCRIPT_DIR/../odoo-monolith-1/app/odoo-src/odoo/addons-enterprise/enterprise-addons.zip" \
    "$SCRIPT_DIR/../odoo-19-images/odoo-19-e1/build-context/enterprise-addons.zip"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

ZIP_SRC="$(resolve_enterprise_zip)" || {
  echo "ERROR: enterprise-addons.zip not found." >&2
  echo "Set ENTERPRISE_ZIP_SRC or place zip in addons-enterprise/." >&2
  exit 1
}

echo "Using enterprise zip: $ZIP_SRC"
cp "$ZIP_SRC" "$BUILD_CONTEXT/enterprise-addons.zip"

docker build --platform "$PLATFORM" -t "${IMAGE_REPO}:latest" "$BUILD_CONTEXT"
echo "OK built ${IMAGE_REPO}:latest"

if [[ "${PUSH:-0}" == "1" ]]; then
  docker push "${IMAGE_REPO}:latest"
  echo "OK pushed ${IMAGE_REPO}:latest"
fi
