#!/usr/bin/env bash
# Factory bootstrap: fetch deploy-repo tarball, exec git entrypoint (SSOT), else baked fallback.
set -euo pipefail

configure_locale() {
  export LANGUAGE=
  if locale -a 2>/dev/null | grep -qi 'en_us.utf-8'; then
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
  else
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
  fi
}
configure_locale

log() { printf '[odoo-bootstrap] %s\n' "$*" >&2; }

entrypoint_is_legacy() {
  local f="$1"
  grep -qE '\[r2-app\]|db-r2\.railway\.internal|ODOO_DB:-r2_|CONFIG_PROFILE:-r2-' "$f"
}

fetch_boot_overlay() {
  case "${ADDONS_GIT_DISABLE:-0}" in 1|true|True|yes|YES) return 0 ;; esac
  [[ -z "${ADDONS_GIT_REF:-}" ]] && return 0
  [[ -n "${ADDONS_GIT_EXTRACT:-}" && -d "${ADDONS_GIT_EXTRACT}" ]] && return 0

  local repo="${ADDONS_GIT_REPO:-rjr3000/odoo-19-all}"
  local tmp auth=()
  tmp=$(mktemp -d)
  if [[ -n "${GH_ADDONS_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GH_ADDONS_TOKEN}")
  fi
  log "Fetching boot overlay from ${repo}@${ADDONS_GIT_REF}..."
  if curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/tarball/${ADDONS_GIT_REF}" -o "$tmp/src.tgz"; then
    mkdir -p "$tmp/x"
    tar -xzf "$tmp/src.tgz" -C "$tmp/x" --strip-components=1
    export ADDONS_GIT_EXTRACT="$tmp/x"
    log "Boot overlay ready"
  else
    log "WARN: boot overlay fetch failed; using baked entrypoint"
  fi
}

resolve_entrypoint() {
  local candidate baked="/usr/local/bin/entrypoint-odoo-app.baked"
  if [[ -n "${ADDONS_GIT_EXTRACT:-}" ]]; then
    for candidate in \
      "${ADDONS_GIT_EXTRACT}/servers/railway/odoo-19-r2/entrypoint-odoo-app.sh" \
      "${ADDONS_GIT_EXTRACT}/hosts/railway/odoo-19-r2/entrypoint-odoo-app.sh"; do
      if [[ -f "$candidate" ]]; then
        if entrypoint_is_legacy "$candidate"; then
          log "WARN: ignoring legacy git entrypoint (r2 hardcoding): $candidate"
          continue
        fi
        log "Using entrypoint from git (${ADDONS_GIT_REF})"
        printf '%s' "$candidate"
        return 0
      fi
    done
    if [[ -f "${ADDONS_GIT_EXTRACT}/servers/railway/odoo-19-r2/entrypoint-r2-app.sh" ]] \
      || [[ -f "${ADDONS_GIT_EXTRACT}/hosts/railway/odoo-19-r2/entrypoint-r2-app.sh" ]]; then
      log "WARN: git has entrypoint-r2-app.sh only — use entrypoint-odoo-app.sh on main; falling back to baked"
    fi
  fi
  log "Using baked entrypoint"
  printf '%s' "$baked"
}

fetch_boot_overlay
exec bash "$(resolve_entrypoint)"
