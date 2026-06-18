#!/usr/bin/env bash
# Factory Odoo 19 app entrypoint (split Postgres + Odoo, odoo-19-app-1 image).
# - Root start for /var/lib/odoo volume chown (RAILWAY_RUN_UID=0)
# - ADDONS_GIT_* overlay from deploy repo
# - CONFIG_PROFILE merge from /opt/railway-host-profiles/<profile>/
# - Remote Postgres bootstrap + module reconcile (no volume delete)
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

log() { printf '[odoo-app] %s\n' "$*"; }

odoo_is_verbose() {
  case "${ODOO_APP_VERBOSE:-${R2_APP_VERBOSE:-0}}${ODOO_LIST_ADDONS:-0}" in
    *1*|*true*|*True*|*yes*|*YES*) return 0 ;;
  esac
  return 1
}

log_v() {
  odoo_is_verbose || return 0
  log "$@"
}

normalize_config_profile() {
  case "${1}" in
    r2-dev|dev) printf '%s' "odoo-dev" ;;
    r2-live|live) printf '%s' "odoo-live" ;;
    r2-test|test) printf '%s' "odoo-test" ;;
    *) printf '%s' "${1}" ;;
  esac
}

escape_sed_repl() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g' -e 's/\$/\\$/g'
}

set_odoo_conf_option() {
  local key="$1" value="$2" escaped
  [[ -z "$value" ]] && return 0
  escaped="$(escape_sed_repl "$value")"
  if grep -q "^${key} = " "$ODOO_CONF" 2>/dev/null; then
    sed -i "s|^${key} = .*|${key} = ${escaped}|" "$ODOO_CONF"
  else
    printf '%s = %s\n' "$key" "$value" >>"$ODOO_CONF"
  fi
}

DB_NAME="${ODOO_DB:-${POSTGRES_DB:-odoo}}"
CONFIG_PROFILE="$(normalize_config_profile "${CONFIG_PROFILE:-odoo-live}")"
PGHOST="${PGHOST:-${HOST:-odoo-db-1.railway.internal}}"
PGPORT="${PGPORT:-5432}"
PGUSER="${USER:-odoo}"
PGPASSWORD="${PASSWORD:-}"
export PGPASSWORD
ODOO_CMD="${ODOO_CMD:-odoo}"
ODOO_CONF="${ODOO_RC:-/etc/odoo/odoo.conf}"
HTTP_PORT="${ODOO_HTTP_PORT:-${PORT:-8069}}"
FILESTORE_ROOT="/var/lib/odoo/filestore/${DB_NAME}"
ADDONS_GIT_EXTRACT=""
JUST_INITIALIZED=0

apply_odoo_conf_from_env() {
  if [[ -n "${ODOO_ADMIN_PASSWD:-}" ]]; then set_odoo_conf_option admin_passwd "${ODOO_ADMIN_PASSWD}"; fi
  if [[ -n "${ODOO_GEVENT_PORT:-}" ]]; then set_odoo_conf_option gevent_port "${ODOO_GEVENT_PORT}"; fi
  if [[ -n "${ODOO_HTTP_PORT:-}" ]]; then set_odoo_conf_option http_port "${ODOO_HTTP_PORT}"; fi
  if [[ -n "${ODOO_WORKERS:-}" ]]; then set_odoo_conf_option workers "${ODOO_WORKERS}"; fi
  if [[ -n "${ODOO_MAX_CRON_THREADS:-}" ]]; then set_odoo_conf_option max_cron_threads "${ODOO_MAX_CRON_THREADS}"; fi
  if [[ -n "${ODOO_DEV_MODE:-}" ]]; then set_odoo_conf_option dev_mode "${ODOO_DEV_MODE}"; fi
  if [[ -n "${ODOO_LOG_LEVEL:-}" ]]; then set_odoo_conf_option log_level "${ODOO_LOG_LEVEL}"; fi
  if [[ -n "${ODOO_DB_MAXCONN:-}" ]]; then set_odoo_conf_option db_maxconn "${ODOO_DB_MAXCONN}"; fi
  if [[ -n "${ODOO_LIMIT_MEMORY_SOFT:-}" ]]; then set_odoo_conf_option limit_memory_soft "${ODOO_LIMIT_MEMORY_SOFT}"; fi
  if [[ -n "${ODOO_LIMIT_MEMORY_HARD:-}" ]]; then set_odoo_conf_option limit_memory_hard "${ODOO_LIMIT_MEMORY_HARD}"; fi
  if [[ -n "${ODOO_LIMIT_TIME_CPU:-}" ]]; then set_odoo_conf_option limit_time_cpu "${ODOO_LIMIT_TIME_CPU}"; fi
  if [[ -n "${ODOO_LIMIT_TIME_REAL:-}" ]]; then set_odoo_conf_option limit_time_real "${ODOO_LIMIT_TIME_REAL}"; fi
  if [[ -n "${ODOO_LIMIT_TIME_REAL_CRON:-}" ]]; then set_odoo_conf_option limit_time_real_cron "${ODOO_LIMIT_TIME_REAL_CRON}"; fi
  case "${ODOO_PROXY_MODE:-}" in
    1|true|True|yes|YES) set_odoo_conf_option proxy_mode True ;;
    0|false|False|no|NO) set_odoo_conf_option proxy_mode False ;;
  esac
  local smtp_host="${ODOO_SMTP_HOST:-}"
  local smtp_port="${ODOO_SMTP_PORT:-${ODOO_SMTP_PORT_NUMBER:-}}"
  if [[ -n "$smtp_host" ]]; then set_odoo_conf_option smtp_server "$smtp_host"; fi
  if [[ -n "$smtp_port" ]]; then set_odoo_conf_option smtp_port "$smtp_port"; fi
  if [[ -n "${ODOO_SMTP_USER:-}" ]]; then set_odoo_conf_option smtp_user "${ODOO_SMTP_USER}"; fi
  if [[ -n "${ODOO_SMTP_PASSWORD:-}" ]]; then set_odoo_conf_option smtp_password "${ODOO_SMTP_PASSWORD}"; fi
  if [[ -n "${ODOO_EMAIL_FROM:-}" ]]; then set_odoo_conf_option email_from "${ODOO_EMAIL_FROM}"; fi
  case "${ODOO_SMTP_SSL:-}" in
    1|true|True|yes|YES) set_odoo_conf_option smtp_ssl True ;;
    0|false|False|no|NO) set_odoo_conf_option smtp_ssl False ;;
  esac
  if [[ -n "${ODOO_ADDONS_PATH:-}" ]]; then set_odoo_conf_option addons_path "${ODOO_ADDONS_PATH}"; fi
}

merge_module_lists() {
  local out="" item arg
  for arg in "$@"; do
    [[ -z "$arg" ]] && continue
    local IFS=','
    for item in $arg; do
      item="$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ -z "$item" ]] && continue
      if [[ ",${out}," != *",${item},"* ]]; then
        out="${out:+$out,}${item}"
      fi
    done
  done
  printf '%s' "$out"
}

read_init_modules_file() {
  local init_file="/opt/odoo/database/init-modules.txt"
  [[ -f "$init_file" ]] || return 0
  grep -v '^#' "$init_file" | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d' | paste -sd, -
}

write_init_modules_file() {
  local modules="$1" source="$2"
  mkdir -p /opt/odoo/database
  {
    printf '# %s\n' "$source"
    printf '%s\n' "$modules"
  } >/opt/odoo/database/init-modules.txt
}

apply_module_env() {
  local modules="" base="${ODOO_BASE_MODULES:-}" custom="${ODOO_CUSTOM_MODULES:-}"
  if [[ -n "${ODOO_INIT_MODULES:-}" ]]; then
    modules="$ODOO_INIT_MODULES"
    write_init_modules_file "$modules" "ODOO_INIT_MODULES override"
    log_v "init-modules -> ${modules}"
    return 0
  fi
  if [[ -n "$base$custom" ]]; then
    [[ -z "$base" ]] && base="base,web"
    modules="$(merge_module_lists "$base" "$custom")"
    write_init_modules_file "$modules" "ODOO_BASE_MODULES + ODOO_CUSTOM_MODULES"
    log_v "init-modules (base+custom) -> ${modules}"
    return 0
  fi
  modules="$(read_init_modules_file)"
  if [[ -n "$modules" ]]; then
    log_v "init-modules from profile/git -> ${modules}"
    return 0
  fi
  write_init_modules_file "base,web" "default"
  log_v "init-modules default -> base,web"
}

list_addons_on_disk() {
  case "${ODOO_LIST_ADDONS:-0}" in 1|true|True|yes|YES) ;; *) return 0 ;; esac
  local paths path found=0 manifest dir name parent
  paths=$(grep '^addons_path' "$ODOO_CONF" 2>/dev/null | sed 's/^addons_path = //' || true)
  [[ -z "$paths" ]] && paths="/opt/odoo/addons-custom/00_custom_templates,/opt/odoo/addons-custom/01_custom_app,/opt/odoo/addons-custom/02_custom_theme,/opt/odoo/enterprise,/usr/lib/python3/dist-packages/odoo/addons"
  log "Listing addons (ODOO_LIST_ADDONS=1)"
  local IFS=','
  for path in $paths; do
    path="$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -d "$path" ]] || continue
    log "  addons_path entry: ${path}"
    while IFS= read -r manifest; do
      dir="$(dirname "$(dirname "$manifest")")"
      name="$(basename "$dir")"
      parent="$(basename "$(dirname "$dir")")"
      case "$parent" in
        00_custom_templates|01_custom_app|02_custom_theme) name="${name} (${parent})" ;;
      esac
      log "    module: ${name}"
      found=$((found + 1))
    done < <(find "$path" -mindepth 1 -maxdepth 3 -name '__manifest__.py' 2>/dev/null | sort)
  done
  log "Listed ${found} addon manifest(s) on disk"
}

write_base_odoo_conf() {
  mkdir -p /etc/odoo
  cat >"$ODOO_CONF" <<'EOF'
[options]
; Generated at boot by entrypoint-odoo-app.sh — profile snippets merged below.
admin_passwd = Devops26!!
data_dir = /var/lib/odoo
addons_path = /opt/odoo/addons-custom/00_custom_templates,/opt/odoo/addons-custom/01_custom_app,/opt/odoo/addons-custom/02_custom_theme,/opt/odoo/enterprise,/usr/lib/python3/dist-packages/odoo/addons
db_port = 5432
list_db = False
db_maxconn = 32
load_language = en_US
proxy_mode = True
http_interface = 0.0.0.0
http_port = 8069
gevent_port = 8072
server_wide_modules = base,rpc,web
workers = 2
max_cron_threads = 1
log_level = info
EOF
}

merge_snippet_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  log_v "Merging $(basename "$file") from ${CONFIG_PROFILE}"
  {
    printf '\n; --- %s ---\n' "$(basename "$file")"
    while IFS= read -r line || [[ -n "$line" ]]; do
      local trimmed="${line#"${line%%[![:space:]]*}"}"
      case "$trimmed" in
        ""|\;*) continue ;;
      esac
      local key="${line%%=*}"
      key="${key// /}"
      if grep -q "^${key}[[:space:]]*=" "$ODOO_CONF" 2>/dev/null; then
        continue
      fi
      printf '%s\n' "$line"
    done < "$file"
  } >>"$ODOO_CONF"
}

apply_config_profile() {
  local profile="${CONFIG_PROFILE}"
  local prof_dir=""
  local legacy_profile=""
  case "$profile" in
    odoo-dev) legacy_profile="r2-dev" ;;
    odoo-live) legacy_profile="r2-live" ;;
    odoo-test) legacy_profile="r2-test" ;;
  esac
  if [[ -n "$ADDONS_GIT_EXTRACT" ]]; then
    for candidate in \
      "$ADDONS_GIT_EXTRACT/servers/railway/odoo-19-r2/${profile}" \
      "$ADDONS_GIT_EXTRACT/servers/railway/odoo-19-r2/${legacy_profile}" \
      "$ADDONS_GIT_EXTRACT/hosts/railway/odoo-19-r2/${profile}" \
      "$ADDONS_GIT_EXTRACT/hosts/railway/odoo-19-r2/${legacy_profile}"; do
      if [[ -d "$candidate" ]]; then
        prof_dir="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$prof_dir" && -d "/opt/railway-host-profiles/${profile}" ]]; then
    prof_dir="/opt/railway-host-profiles/${profile}"
  fi
  if [[ -z "$prof_dir" && -n "$legacy_profile" && -d "/opt/railway-host-profiles/${legacy_profile}" ]]; then
    prof_dir="/opt/railway-host-profiles/${legacy_profile}"
  fi
  write_base_odoo_conf
  if [[ -n "$prof_dir" ]]; then
    merge_snippet_file "$prof_dir/odoo.conf.snippet"
    merge_snippet_file "$prof_dir/odoo-performance.snippet"
    if [[ -f "$prof_dir/init-modules.txt" ]]; then
      mkdir -p /opt/odoo/database
      cp "$prof_dir/init-modules.txt" /opt/odoo/database/init-modules.txt
      log_v "init-modules from profile ${profile}"
    fi
  else
    log "WARN: CONFIG_PROFILE dir not found in git overlay (${profile}); using base odoo.conf"
  fi
}

apply_addons_git_extract() {
  local root="$1"
  [[ -d "$root" ]] || return 1
  ADDONS_GIT_EXTRACT="$root"
  if [[ -d "$root/addons-custom" ]]; then
    rm -rf /opt/odoo/addons-custom
    cp -a "$root/addons-custom" /opt/odoo/addons-custom
  fi
  if [[ -f "$root/database/init-modules.txt" ]]; then
    mkdir -p /opt/odoo/database
    cp "$root/database/init-modules.txt" /opt/odoo/database/init-modules.txt
  fi
  return 0
}

fetch_addons_git_tarball() {
  case "${ADDONS_GIT_DISABLE:-0}" in 1|true|True|yes|YES) return 0 ;; esac
  [[ -z "${ADDONS_GIT_REF:-}" ]] && return 0
  if [[ -n "${ADDONS_GIT_EXTRACT:-}" && -d "${ADDONS_GIT_EXTRACT}" ]]; then
    return 0
  fi
  local repo="${ADDONS_GIT_REPO:-rjr3000/odoo-19-all}"
  local tmp auth=()
  tmp=$(mktemp -d)
  if [[ -n "${GH_ADDONS_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${GH_ADDONS_TOKEN}")
  fi
  log_v "Fetching overlay from ${repo}@${ADDONS_GIT_REF}..."
  if curl -fsSL "${auth[@]}" "https://api.github.com/repos/${repo}/tarball/${ADDONS_GIT_REF}" -o "$tmp/src.tgz"; then
    mkdir -p "$tmp/x"
    tar -xzf "$tmp/src.tgz" -C "$tmp/x" --strip-components=1
    ADDONS_GIT_EXTRACT="$tmp/x"
    return 0
  fi
  log "WARN: could not fetch ${repo}@${ADDONS_GIT_REF}; continuing with image defaults"
  return 1
}

fetch_branch_addons() {
  fetch_addons_git_tarball || return 0
  [[ -n "${ADDONS_GIT_EXTRACT:-}" ]] || return 0
  apply_addons_git_extract "$ADDONS_GIT_EXTRACT"
  log_v "Git overlay applied from ${ADDONS_GIT_REF}"
}

apply_init_modules_override() {
  apply_module_env
}

escape_dbfilter_literal() {
  printf '%s' "$1" | sed 's/[][\\^$.*+?{}|()]/\\&/g'
}

patch_odoo_conf_for_db() {
  local dbfilter="${ODOO_DBFILTER:-}"
  set_odoo_conf_option db_name "${DB_NAME}"
  if [[ -z "$dbfilter" ]]; then
    dbfilter="^$(escape_dbfilter_literal "${DB_NAME}")$"
  fi
  set_odoo_conf_option dbfilter "${dbfilter}"
  case "${ODOO_LIST_DB:-0}" in
    1|true|True|yes|YES) set_odoo_conf_option list_db True ;;
  esac
  apply_odoo_conf_from_env
  log "odoo.conf ready db=${DB_NAME} profile=${CONFIG_PROFILE}"
}

psql_q() {
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -Atqc "$1"
}

wait_for_postgres() {
  log "Waiting for Postgres at ${PGHOST}:${PGPORT}..."
  for _ in $(seq 1 120); do
    if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" >/dev/null 2>&1; then
      log "Postgres is ready"
      return 0
    fi
    sleep 2
  done
  log "ERROR: Postgres not ready"
  exit 1
}

database_exists() {
  [[ "$(psql_q "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null || echo "")" == "1" ]]
}

database_has_odoo_tables() {
  local count
  count=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -Atqc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='ir_module_module'" 2>/dev/null || echo "0")
  [[ "${count:-0}" -gt 0 ]]
}

run_odoo_batch() {
  local batch_log="/tmp/r2-odoo-batch.log"
  if odoo_is_verbose; then
    runuser -u odoo -- "$ODOO_CMD" "$@"
    return $?
  fi
  if runuser -u odoo -- "$ODOO_CMD" "$@" >"$batch_log" 2>&1; then
    return 0
  fi
  log "WARN: Odoo batch step failed; last log lines:"
  tail -15 "$batch_log" | while IFS= read -r line; do log "  ${line}"; done
  return 1
}

ensure_odoo_database() {
  if database_exists && database_has_odoo_tables; then
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -q \
      -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true
    log_v "Database ${DB_NAME} ready (existing schema)"
    return 0
  fi

  if ! database_exists; then
    log "Creating database ${DB_NAME} on ${PGHOST}..."
    createdb -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$DB_NAME"
  else
    log "Database ${DB_NAME} exists; initializing Odoo schema..."
  fi

  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -q \
    -c "CREATE EXTENSION IF NOT EXISTS vector;" >/dev/null 2>&1 || true

  local modules="" init_file="/opt/odoo/database/init-modules.txt"
  local demo_flag="all"
  case "${ODOO_WITHOUT_DEMO:-1}" in
    0|false|False|no|NO) demo_flag="False" ;;
  esac
  [[ -f "$init_file" ]] && modules=$(grep -v '^#' "$init_file" | tr -d '[:space:]' | paste -sd, -)
  [[ -z "$modules" ]] && modules="base,web"

  log "Initial install modules: ${modules}"
  run_odoo_batch server -c "$ODOO_CONF" -d "$DB_NAME" -i "$modules" \
    --stop-after-init --no-http --max-cron-threads=0 --without-demo="$demo_flag"
  log "Database ${DB_NAME} initialized"
  JUST_INITIALIZED=1
}

reconcile_modules() {
  [[ "${JUST_INITIALIZED:-0}" == "1" ]] && return 0
  [[ -f /opt/odoo/database/init-modules.txt ]] || return 0
  [[ "$(database_has_odoo_tables && echo 1 || echo 0)" == "0" ]] && return 0

  local sync_upgrades=1
  case "${ODOO_MODULE_SYNC:-1}" in 0|false|False|no|NO) sync_upgrades=0 ;; esac

  local desired installed m to_install="" to_upgrade=""
  desired=$(grep -v '^#' /opt/odoo/database/init-modules.txt | tr ',' '\n' | sed 's/[[:space:]]//g; /^$/d')
  installed=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$DB_NAME" -Atqc \
    "SELECT name FROM ir_module_module WHERE state='installed'" 2>/dev/null || true)
  for m in $desired; do
    if grep -qx "$m" <<<"$installed"; then
      if [[ "$sync_upgrades" == "1" ]] \
         && { compgen -G "/opt/odoo/addons-custom/*/${m}/__manifest__.py" >/dev/null \
              || compgen -G "/opt/odoo/addons-custom/${m}/__manifest__.py" >/dev/null; }; then
        to_upgrade+="${m},"
      fi
    else
      to_install+="${m},"
    fi
  done
  if [[ -n "${ODOO_INSTALL_MODULES:-}" ]]; then
    to_install+="${ODOO_INSTALL_MODULES},"
  fi
  if [[ "$sync_upgrades" == "1" && -n "${ODOO_UPDATE_MODULES:-}" ]]; then
    to_upgrade+="${ODOO_UPDATE_MODULES},"
  fi
  to_install="${to_install%,}"
  to_upgrade="${to_upgrade%,}"
  [[ -z "$to_install" && -z "$to_upgrade" ]] && return 0

  local -a args=()
  if [[ -n "$to_install" ]]; then
    args+=(-i "$to_install")
  fi
  if [[ -n "$to_upgrade" ]]; then
    args+=(-u "$to_upgrade")
  fi
  log_v "Module sync: install=[${to_install:-none}] upgrade=[${to_upgrade:-none}]"
  if ! run_odoo_batch server -c "$ODOO_CONF" -d "$DB_NAME" "${args[@]}" \
    --stop-after-init --no-http --max-cron-threads=0 --without-demo=all; then
    log "ERROR: module sync failed (install=[${to_install:-none}] upgrade=[${to_upgrade:-none}])"
    case "${ODOO_UPGRADE_VERIFY:-1}" in
      0|false|False|no|NO) log "WARN: ODOO_UPGRADE_VERIFY=0 — continuing despite module sync failure" ;;
      *) exit 1 ;;
    esac
  fi
}

maybe_patch_admin_user() {
  [[ -z "${ODOO_INIT_ADMIN_LOGIN:-}${ODOO_INIT_ADMIN_PASSWORD:-}" ]] && return 0
  case "${ODOO_INIT_ADMIN_FORCE:-0}" in 1|true|True|yes|YES) ;; *)
    [[ "${JUST_INITIALIZED:-0}" != "1" ]] && return 0 ;;
  esac
  log "Applying ODOO_INIT_ADMIN_* to base.user_admin"
  ODOO_CONF="$ODOO_CONF" DB_NAME="$DB_NAME" \
    ODOO_INIT_ADMIN_LOGIN="${ODOO_INIT_ADMIN_LOGIN:-}" \
    ODOO_INIT_ADMIN_PASSWORD="${ODOO_INIT_ADMIN_PASSWORD:-}" \
    runuser -u odoo -- python3 <<'PY'
import os
import odoo
from odoo import SUPERUSER_ID, api

conf = os.environ["ODOO_CONF"]
db = os.environ["DB_NAME"]
odoo.tools.config.parse_config(["-c", conf, "-d", db])
registry = odoo.registry(db)
with registry.cursor() as cr:
    env = api.Environment(cr, SUPERUSER_ID, {})
    user = env.ref("base.user_admin")
    vals = {}
    login = os.environ.get("ODOO_INIT_ADMIN_LOGIN")
    password = os.environ.get("ODOO_INIT_ADMIN_PASSWORD")
    if login:
        vals["login"] = login
    if password:
        vals["password"] = password
    if vals:
        user.write(vals)
        cr.commit()
PY
}

mkdir -p /var/lib/odoo/backups /var/lib/odoo/sessions /var/lib/odoo/filestore

log "Boot db=${DB_NAME} profile=${CONFIG_PROFILE}"

fetch_branch_addons
apply_config_profile
apply_init_modules_override
init_summary="$(read_init_modules_file 2>/dev/null || true)"
[[ -n "$init_summary" ]] && log "modules=${init_summary}"
patch_odoo_conf_for_db

chown -R odoo:odoo /var/lib/odoo /opt/odoo/addons-custom 2>/dev/null || true
chown odoo:odoo "$ODOO_CONF" 2>/dev/null || true

list_addons_on_disk

wait_for_postgres
ensure_odoo_database
maybe_patch_admin_user
reconcile_modules

if [[ "${ODOO_PREDEPLOY_ONLY:-0}" == "1" ]]; then
  log "preDeploy module sync complete for db=${DB_NAME}"
  exit 0
fi

log "Starting Odoo HTTP on ${HTTP_PORT} db=${DB_NAME} profile=${CONFIG_PROFILE}"
exec runuser -u odoo -- /entrypoint.sh odoo -d "${DB_NAME}" --http-port "${HTTP_PORT}"
