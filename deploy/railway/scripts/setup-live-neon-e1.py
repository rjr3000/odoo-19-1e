#!/usr/bin/env python3
"""Apply neon-e1-live.deploy.json: git rjr3000/odoo-19-1e + Neon odoo-19-e1 on Railway live."""
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


def neon_connection_uri(api_key: str, project_id: str, branch_id: str, database_name: str) -> str:
    import urllib.request

    url = (
        f"{NEON_API}/projects/{project_id}/connection_uri"
        f"?branch_id={branch_id}&database_name={database_name}&role_name=neondb_owner&pooled=true"
    )
    req = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {api_key}", "Accept": "application/json"},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode())
    uri = data.get("uri")
    if not uri:
        raise SystemExit(f"Neon connection_uri missing for {database_name}")
    return uri


def parse_neon_url(uri: str) -> dict[str, str]:
    p = urlparse(uri)
    return {
        "ODOO_DATABASE_HOST": p.hostname or "",
        "ODOO_DATABASE_PORT": str(p.port or 5432),
        "ODOO_DATABASE_USER": unquote(p.username or ""),
        "ODOO_DATABASE_PASSWORD": unquote(p.password or ""),
    }


def resolve_secrets() -> dict[str, str]:
    smtp = (
        os.environ.get("SMTP_PASSWORD")
        or os.environ.get("MAIL_SHARED_PASSWORD")
        or os.environ.get("SHARED_LOGIN_PASSWORD")
        or os.environ.get("VS1_PASSWORD")
        or os.environ.get("ACCOUNT_PASSWORD")
        or ""
    )
    gh = os.environ.get("GH_ADDONS_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    out: dict[str, str] = {}
    if smtp:
        out["ODOO_SMTP_PASSWORD"] = smtp
        out["ODOO_SMTP_HOST"] = "mail.rg1.io"
        out["ODOO_SMTP_PORT_NUMBER"] = "587"
        out["ODOO_SMTP_USER"] = "admin@mvs.rg1.io"
        out["ODOO_EMAIL_FROM"] = "admin@mvs.rg1.io"
    if gh:
        out["GH_ADDONS_TOKEN"] = gh
    return out


def main() -> None:
    load_dotenv(ROOT.parent / "agents-all" / "y_secrets" / "local.env")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    ref = manifest["reference"]
    neon = manifest["neon"]
    git = manifest["git"]
    project_id = ref["project_id"]
    env_id = ref["environment_id"]
    service_id = ref["service_id"]

    neon_key = os.environ.get("NEON_API_KEY")
    if not neon_key:
        raise SystemExit("NEON_API_KEY required in agents-all/y_secrets/local.env")

    uri = neon_connection_uri(
        neon_key,
        neon["project_id"],
        neon["branch_id"],
        neon["database_name"],
    )
    neon_parts = parse_neon_url(uri)

    rt = load_rt()
    os.environ["RAILWAY_PROJECT_ID"] = project_id

    vars_map = dict(manifest["variables"])
    vars_map.update(neon_parts)
    vars_map["ODOO_DATABASE_NAME"] = neon["database_name"]
    vars_map.update(resolve_secrets())
    for key, val in (manifest.get("build_variables") or {}).items():
        if not str(val).startswith("<"):
            vars_map.setdefault(key, val)

    print(f"Neon host={neon_parts['ODOO_DATABASE_HOST']} db={neon['database_name']}")
    print(f"Git={git['repo']}@{git['branch']} dockerfile={git['dockerfile']}")

    rt.upsert_variables(service_id, env_id, vars_map)
    print(f"UPSERTED vars ({len(vars_map)}): {', '.join(sorted(vars_map.keys()))}")

    deploy = manifest["deploy"]
    try:
        rt.gql(
            """
            mutation($id: String!, $input: ServiceConnectInput!) {
              serviceConnect(id: $id, input: $input) { id name }
            }
            """,
            {"id": service_id, "input": {"repo": git["repo"], "branch": git["branch"]}},
        )
        print(f"CONNECTED git {git['repo']}@{git['branch']}")
    except SystemExit as exc:
        print(f"WARN: git connect ({exc}) — continuing if already connected")

    rt.update_service_instance(
        service_id,
        env_id,
        {
            "railwayConfigFile": git["railway_config_file"],
            "startCommand": deploy["startCommand"],
            "healthcheckPath": deploy.get("healthcheckPath"),
            "healthcheckTimeout": deploy.get("healthcheckTimeout"),
        },
    )
    print("UPDATED railway.json + startCommand + healthcheck (git Dockerfile build)")

    dep = rt.deploy_service(service_id, env_id)
    print(f"DEPLOY workflow={dep}")


if __name__ == "__main__":
    main()
