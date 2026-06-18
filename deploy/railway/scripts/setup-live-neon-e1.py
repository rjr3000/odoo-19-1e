#!/usr/bin/env python3
"""Apply neon-e1-live.deploy.json — fresh, no stock-template vars."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[3]
MANIFEST = Path(__file__).resolve().parent.parent / "neon-e1-live.deploy.json"
RT_PATH = (
    ROOT.parent
    / "odoo-19-all"
    / "servers"
    / "railway"
    / "odoo-19-railway-templates"
    / "scripts"
    / "railway_template.py"
)
NEON_API = "https://console.neon.tech/api/v2"

PURGE_VARS = (
    "ODOO_DATABASE_HOST",
    "ODOO_DATABASE_PORT",
    "ODOO_DATABASE_USER",
    "ODOO_DATABASE_PASSWORD",
    "ODOO_DATABASE_NAME",
    "ODOO_ADDONS_PATH",
    "ENTERPRISE_ZIP_URL",
    "ENTERPRISE_MANIFEST_URL",
    "GH_ADDONS_TOKEN",
    "ENTERPRISE_DELIVERY",
    "ODOO_DB_INIT",
    "ODOO_INIT_MODULES",
    "ODOO_SMTP_HOST",
    "ODOO_SMTP_PORT_NUMBER",
    "ODOO_SMTP_USER",
    "ODOO_SMTP_PASSWORD",
    "ODOO_EMAIL_FROM",
    "CONFIG_PROFILE",
    "ODOO_DB",
    "PGHOST",
    "WEB_BASE_URL",
)


def load_rt():
    spec = importlib.util.spec_from_file_location("railway_template", RT_PATH)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    mod.load_env()
    return mod


def load_dotenv(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip().strip("'").strip('"'))


def neon_uri(api_key: str, project_id: str, branch_id: str, database: str) -> str:
    import urllib.request

    url = (
        f"{NEON_API}/projects/{project_id}/connection_uri"
        f"?branch_id={branch_id}&database_name={database}&role_name=neondb_owner&pooled=true"
    )
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode())
    uri = data.get("uri")
    if not uri:
        raise SystemExit(f"No Neon URI for {database}")
    return uri


def parse_neon(uri: str) -> dict[str, str]:
    p = urlparse(uri)
    return {
        "PGHOST": p.hostname or "",
        "PGPORT": str(p.port or 5432),
        "PGUSER": unquote(p.username or ""),
        "PGPASSWORD": unquote(p.password or ""),
    }


def main() -> None:
    load_dotenv(ROOT.parent / "agents-all" / "y_secrets" / "local.env")
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    neon_key = os.environ.get("NEON_API_KEY")
    if not neon_key:
        raise SystemExit("NEON_API_KEY required")

    uri = neon_uri(
        neon_key,
        m["neon"]["project_id"],
        m["neon"]["branch_id"],
        m["neon"]["database_name"],
    )
    vars_map = dict(m["variables"])
    vars_map.update(parse_neon(uri))

    rt = load_rt()
    pid = m["reference"]["project_id"]
    eid = m["reference"]["environment_id"]
    sid = m["reference"]["service_id"]
    os.environ["RAILWAY_PROJECT_ID"] = pid

    for name in PURGE_VARS:
        try:
            rt.gql(
                "mutation($input: VariableDeleteInput!) { variableDelete(input: $input) }",
                {
                    "input": {
                        "projectId": pid,
                        "environmentId": eid,
                        "serviceId": sid,
                        "name": name,
                        "skipDeploys": True,
                    }
                },
            )
            print(f"purged {name}")
        except SystemExit:
            pass

    rt.upsert_variables(sid, eid, vars_map)
    print(f"set official Odoo Docker vars: {', '.join(sorted(vars_map.keys()))}")

    d = m["deploy"]
    rt.update_service_instance(
        sid,
        eid,
        {
            "rootDirectory": m["git"]["root_directory"],
            "railwayConfigFile": m["git"]["railway_config_file"],
            "startCommand": d["startCommand"],
            "healthcheckPath": d["healthcheckPath"],
            "healthcheckTimeout": d["healthcheckTimeout"],
        },
    )
    print("updated service instance from neon-e1-live.deploy.json")

    dep = rt.deploy_service(sid, eid)
    print(f"deploy={dep}")


if __name__ == "__main__":
    main()
