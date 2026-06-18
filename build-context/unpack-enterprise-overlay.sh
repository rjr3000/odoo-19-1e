#!/usr/bin/env bash
# Unpack enterprise-addons.zip into ODOO_PATH_ENTERPRISE (python3 — no unzip apt).
set -euo pipefail

ZIP="${ENTERPRISE_ZIP_PATH:-}"
DEST="${ODOO_PATH_ENTERPRISE:-/opt/odoo/enterprise}"

if [[ -z "$ZIP" ]]; then
  for candidate in \
    "/tmp/enterprise-addons.zip" \
    "/app/enterprise-addons.zip"; do
    if [[ -f "$candidate" ]]; then
      ZIP="$candidate"
      break
    fi
  done
fi

log() { printf '[unpack-enterprise] %s\n' "$*"; }

if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  log "ERROR: enterprise zip not found"
  exit 1
fi

mkdir -p "$DEST"

python3 - "$ZIP" "$DEST" <<'PY'
import os
import shutil
import sys
import zipfile

zip_path, dest = sys.argv[1], sys.argv[2]
keep = {"README.md", "install-modules.txt", ".gitkeep", "enterprise-addons.zip", "enterprise-overlay-manifest.json", "requirements.txt"}

with zipfile.ZipFile(zip_path) as zf:
    names = [n for n in zf.namelist() if n and not n.endswith("/")]
    if not names:
        raise SystemExit("zip is empty")

    top_levels = {n.split("/", 1)[0] for n in names}
    flat = not any("/" in n for n in names)

    for entry in os.listdir(dest):
        if entry in keep:
            continue
        path = os.path.join(dest, entry)
        if os.path.isdir(path):
            shutil.rmtree(path)
        elif os.path.isfile(path):
            os.remove(path)

    extracted = 0
    if flat:
        zf.extractall(dest)
        extracted = len(top_levels)
    else:
        tmp = dest + ".unpack_tmp"
        if os.path.isdir(tmp):
            shutil.rmtree(tmp)
        os.makedirs(tmp, exist_ok=True)
        zf.extractall(tmp)
        children = [c for c in os.listdir(tmp) if not c.startswith(".")]
        if len(children) == 1 and os.path.isdir(os.path.join(tmp, children[0])):
            src_root = os.path.join(tmp, children[0])
        else:
            src_root = tmp
        for name in os.listdir(src_root):
            if name in keep:
                continue
            src = os.path.join(src_root, name)
            dst = os.path.join(dest, name)
            if os.path.isdir(dst):
                shutil.rmtree(dst)
            if os.path.isdir(src):
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)
            extracted += 1
        shutil.rmtree(tmp, ignore_errors=True)

    if extracted < 50:
        raise SystemExit(f"too few enterprise modules unpacked: {extracted}")
    print(f"unpacked {extracted} top-level entries into {dest}")
PY

chmod -R a+rwX "$DEST" 2>/dev/null || true
log "Enterprise overlay ready at $DEST"
