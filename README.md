# odoo-19-1e

Odoo **19.0 + enterprise** Docker image that mimics the **factory production build** (`evoluzion26/odoo-19-app-1`) used by the Railway workspace template **`odoo-19-live-2-template`** (`code: y08k2y`).

Companion to the stock **Odoo 19** Railway template (`odoo:19.0` + `postgres-ssl:16`) — adds baked enterprise, factory entrypoint, and `railway-host-profiles`.

## Railway project `odoo-19-2` (inspected 2026-06-18)

| Item | Value |
|------|-------|
| Project ID | `2a51ef71-b79e-4492-ac8c-c7aaef65c342` |
| Environment | `production` (`f42d1e73-44b8-406c-96b9-50e64d796555`) |
| **Postgres** service | Image `ghcr.io/railwayapp-templates/postgres-ssl:16` |
| **Odoo** service | Image `odoo:19.0` (stock — no enterprise) |
| Start command | Stock Odoo CLI with `ODOO_DATABASE_*` env wiring |
| Healthcheck | `/web/health` |
| Template source | Stock sidebar template **Odoo 19** (not factory live template) |

## Production factory template (workspace)

| Item | Value |
|------|-------|
| Template name | `odoo-19-live-2-template` |
| Template code | `y08k2y` |
| Template ID | `441fd2a1-8e43-414e-a3bf-f7b4e1ca8103` |
| DB image | `evoluzion26/odoo-19-db-1:latest` |
| App image | `evoluzion26/odoo-19-app-1:latest` |
| Start command | `/usr/local/bin/entrypoint-odoo-app.sh` |
| Config profile (live) | `CONFIG_PROFILE=odoo-live` |
| HTTP port | **8069** (`targetPort` on Railway domains) |
| SSOT config | `odoo-19-all/servers/railway/odoo-19-railway-templates/serializedConfig.r2-live-factory.json` |

**This repo** reproduces the **app image build** (enterprise + entrypoint + host profiles). Pair with `evoluzion26/odoo-19-db-1` or any Postgres 16+ service for a full factory stack.

## Build

```bash
# Place enterprise zip in addons-enterprise/ or set ENTERPRISE_ZIP_SRC
export ENTERPRISE_ZIP_SRC="/path/to/enterprise-addons.zip"   # optional

bash build.sh
PUSH=1 bash build.sh   # after docker login
```

Default image name: `evoluzion26/odoo-19-1e:latest` (override with `ODOO_IMAGE_REPO`).

Enterprise zip is resolved from (first match):

- `addons-enterprise/enterprise-addons.zip` (this repo)
- `../odoo-19-d2/addons-enterprise/enterprise-addons.zip`
- `../odoo-19-all/addons-enterprise/enterprise-addons.zip`
- `../odoo-monolith-1/app/odoo-src/odoo/addons-enterprise/enterprise-addons.zip`

## Railway deploy — stock production template (NOT template 2)

**SSOT:** `deploy/railway/stock-production.deploy.json`

Use this to attach **this repo** to an environment matching the sidebar template **Odoo 19** (same graph as project `odoo-19-2`) — **not** `odoo-19-live-2-template` / factory template 2.

| Item | Stock production | Factory template 2 (do not use here) |
|------|------------------|--------------------------------------|
| Postgres | `postgres-ssl:16` | `evoluzion26/odoo-19-db-1` |
| Odoo source | Git → this repo | `evoluzion26/odoo-19-app-1` image |
| DB env | `ODOO_DATABASE_*` | `ODOO_DB`, `PGHOST`, `HOST` |
| Start | Stock `odoo` CLI + wait-for-Postgres | `/usr/local/bin/entrypoint-odoo-app.sh` |
| Profile | none | `CONFIG_PROFILE=odoo-live` |

**Quick steps:**

1. Deploy from sidebar **Odoo 19** (or use existing `odoo-19-2`).
2. Connect Odoo service to `rjr3000/odoo-19-1e` · Config file `/railway.json`.
3. Paste vars from `deploy/railway/railway.variables.stock-production.env.example`.
4. Volume `/var/lib/odoo` · target port **8069** · healthcheck `/web/health`.

See `stock-production.deploy.json` for full service graph, forbidden factory vars, and step list.

## Baked vs runtime

| Baked in image | Supplied at deploy |
|----------------|-------------------|
| Odoo 19 CE + EE at `/opt/odoo/enterprise` | `addons-custom/` via `ADDONS_GIT_*` |
| `entrypoint-odoo-app.sh` bootstrap + baked fallback | `ODOO_DB`, SMTP, workers, admin password |
| `/opt/railway-host-profiles/{odoo-dev,odoo-live,odoo-test}` | `CONFIG_PROFILE` |
| Supplemental pip packages | Postgres service + volumes |

## Related

- Factory image SSOT: `odoo-19-images/odoo-19-app-1/`
- Stock Railway template: `odoo-19-all/servers/railway/odoo-19-stock-template/`
- Skill: **S05-railway-1** · **S05-dockerhub-1**
