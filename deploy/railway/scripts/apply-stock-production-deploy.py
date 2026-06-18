#!/usr/bin/env python3
"""Apply stock-production.deploy.json to Railway project odoo-19-2 and redeploy Odoo."""
from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).resolve().parent.parent / "stock-production.deploy.json"
RT_PATH = (
    ROOT.parent
    / "odoo-19-all"
    / "servers"
    / "railway"
    / "odoo-19-railway-templates"
    / "scripts"
    / "railway_template.py"
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
        key, val = key.strip(), val.strip().strip("'").strip('"')
        if val.startswith("${") and val.endswith("}"):
            ref = val[2:-1]
            val = os.environ.get(ref, val)
        os.environ.setdefault(key, val)


def resolve_secret_vars() -> dict[str, str]:
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
    if gh:
        out["GH_ADDONS_TOKEN"] = gh
    return out


def service_ids(rt, project_id: str, env_id: str) -> dict[str, str]:
    data = rt.gql(
        """
        query($eid: String!) {
          environment(id: $eid) {
            serviceInstances { edges { node { serviceId serviceName } } }
          }
        }
        """,
        {"eid": env_id},
    )
    out: dict[str, str] = {}
    for edge in data["environment"]["serviceInstances"]["edges"]:
        node = edge["node"]
        out[node["serviceName"]] = node["serviceId"]
    return out


def delete_variable(rt, project_id: str, env_id: str, service_id: str, name: str) -> None:
    try:
        rt.gql(
            """
            mutation($input: VariableDeleteInput!) {
              variableDelete(input: $input)
            }
            """,
            {
                "input": {
                    "projectId": project_id,
                    "environmentId": env_id,
                    "serviceId": service_id,
                    "name": name,
                    "skipDeploys": True,
                }
            },
        )
        print(f"deleted forbidden var {name}")
    except SystemExit as exc:
        msg = str(exc).lower()
        if "not found" in msg or "does not exist" in msg:
            return
        print(f"WARN: delete {name}: {exc}")


def connect_git(rt, service_id: str, repo: str, branch: str) -> None:
    rt.gql(
        """
        mutation($id: String!, $input: ServiceConnectInput!) {
          serviceConnect(id: $id, input: $input) { id name }
        }
        """,
        {"id": service_id, "input": {"repo": repo, "branch": branch}},
    )
    print(f"connected git {repo}@{branch}")


def fix_target_port(rt, project_id: str, env_id: str, service_id: str, port: int) -> None:
    data = rt.gql(
        """
        query($projectId: String!, $environmentId: String!, $serviceId: String!) {
          domains(projectId: $projectId, environmentId: $environmentId, serviceId: $serviceId) {
            serviceDomains { id domain targetPort }
            customDomains { id domain targetPort }
          }
        }
        """,
        {
            "projectId": project_id,
            "environmentId": env_id,
            "serviceId": service_id,
        },
    )
    domains = data.get("domains") or {}
    for bucket in ("serviceDomains", "customDomains"):
        for item in domains.get(bucket) or []:
            if item.get("targetPort") == port:
                continue
            rt.gql(
                """
                mutation($id: String!, $input: ServiceDomainUpdateInput!) {
                  serviceDomainUpdate(id: $id, input: $input) { id targetPort }
                }
                """,
                {"id": item["id"], "input": {"targetPort": port}},
            )
            print(f"targetPort {item.get('domain')} -> {port}")


def main() -> None:
    agents = ROOT.parent / "agents-all"
    load_dotenv(agents / "y_secrets" / "local.env")

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    ref = manifest["reference"]
    git = manifest["git"]
    pg_spec = manifest["services"]["Postgres"]
    odoo_spec = manifest["services"]["Odoo"]

    rt = load_rt()
    project_id = ref["project_id"]
    env_id = ref["environment_id"]
    os.environ["RAILWAY_PROJECT_ID"] = project_id

    ids = service_ids(rt, project_id, env_id)
    pg_id = ids.get("Postgres")
    odoo_id = ids.get("Odoo")
    if not pg_id or not odoo_id:
        raise SystemExit(f"Missing services in {ref['project']}: {ids}")

    secrets = resolve_secret_vars()
    pg_vars = dict(pg_spec["variables"])
    odoo_vars = dict(odoo_spec["variables"])
    odoo_vars.update(secrets)
    build_vars = odoo_spec.get("build_variables") or {}
    for key, val in build_vars.items():
        if val.startswith("<"):
            continue
        odoo_vars.setdefault(key, val)
    if secrets.get("GH_ADDONS_TOKEN"):
        odoo_vars["GH_ADDONS_TOKEN"] = secrets["GH_ADDONS_TOKEN"]

    connect_git(rt, odoo_id, git["repo"], git["branch"])

    deploy = odoo_spec["deploy"]
    rt.update_service_instance(
        odoo_id,
        env_id,
        {
            "railwayConfigFile": git["railway_config_file"],
            "startCommand": deploy["startCommand"],
            "healthcheckPath": deploy.get("healthcheckPath"),
            "healthcheckTimeout": deploy.get("healthcheckTimeout"),
        },
    )
    print("updated Odoo service instance (config, start, healthcheck)")

    rt.upsert_variables(pg_id, env_id, pg_vars)
    print(f"upserted Postgres vars ({len(pg_vars)})")

    rt.upsert_variables(odoo_id, env_id, odoo_vars)
    print(f"upserted Odoo vars ({len(odoo_vars)})")

    for name in manifest.get("forbidden_variables", []):
        delete_variable(rt, project_id, env_id, odoo_id, name)

    fix_target_port(rt, project_id, env_id, odoo_id, manifest["networking"]["odoo_target_port"])

    dep_id = rt.deploy_service(odoo_id, env_id)
    print(f"deploy triggered workflow={dep_id}")
    print(f"project={ref['project']} env={ref['environment']} odoo_service={odoo_id}")


if __name__ == "__main__":
    main()
