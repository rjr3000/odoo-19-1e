# r2-live — Railway `odoo-19-r2` environment **live**

| Item | Value |
|------|--------|
| Project | `odoo-19-r2` (`f29d478a-630d-44eb-b294-304197395ad1`) |
| Environment | **live** (`70e7fd8c-2ffc-48cb-9fb1-bcade7cf6541`) |
| Postgres service | `odoo-db-1` |
| Odoo service | `odoo-app-1` |
| DB | `r2_live` |
| Public URL | https://r2-live.up.railway.app |
| Custom URL | https://live.odoo.ink |
| Railway target port | **8080** (`r2-live` Networking; Odoo edge) |
| Bus URL (optional) | https://r2-live-bus.up.railway.app → **8072** |
| Internal Postgres | `odoo-db-1.railway.internal:5432` (not public) |
| Platform repo | `/opt/odoo-19/odoo-19-r2` (`_railway/`) |
| Live template deploy | https://railway.com/deploy/v6VUj7-4950691c-e8af-491c-ba88-755f650d2bc5?referralCode=H7nW2o&utm_medium=integration&utm_source=template&utm_campaign=generic |

## Deploy

1. Push **odoo-19-all** (`rjr3000/odoo-19-all`); note SHA (or merge to `main` and let `.github/workflows/railway-r2-deploy.yml` set `ADDONS_GIT_REF`).
2. On Railway **odoo-app-1** (env **live**):

```
ADDONS_GIT_REPO=rjr3000/odoo-19-all
ADDONS_GIT_REF=<sha-or-main>
CONFIG_PROFILE=r2-live
ODOO_DB=r2_live
PGHOST=odoo-db-1.railway.internal
PGPORT=5432
```

3. Redeploy **odoo-app-1** for addon/config overlay changes. Redeploy **odoo-db-1** only when Postgres tuning or image changes are explicitly approved — routine addon CI never touches `odoo-db-1`.

Target images: `odoo-19-db-1` + `odoo-19-app-1` on Railway (today: `evoluzion26/odoo-19-db-1` / legacy `pgvector-odoo:20260604_004122` + `evoluzion26/odoo-19-do:railway-live2`). VM factory pair: `evoluzion26/odoo-19-db-1` + `evoluzion26/odoo-19-app-1`.

## Volumes and addons

| Mount | Path | Role |
|-------|------|------|
| `volume-odoo-app-1` | `/var/lib/odoo` | Filestore for `r2_live`, sessions, backups — **not** custom addon source |
| Postgres volume on `odoo-db-1` | `/var/lib/postgresql` | All live databases; includes `r2_live` and backup DB `live2_rg1` |

Custom addons: fetched at start from `ADDONS_GIT_REPO` + `ADDONS_GIT_REF` into `/opt/odoo/addons-custom/` (container overlay). Do **not** add a separate floating addons volume. See [../docs/r2-VOLUMES.md](../docs/r2-VOLUMES.md).

**Recovery:** never `DROP DATABASE r2_live` without a verified restore path; empty recreate auto-inits `base,web` only. Clone from `live2_rg1` + copy filestore if recovery is needed.

## Config

- `odoo.conf.snippet` — split-stack DB wiring via env
- `odoo-performance.snippet` — live-parity worker block
- `postgres-tuning.args` — apply on **odoo-db-1** start command (`cron.database_name=r2_live`)

## Stack row

`02_apps-1.csv` -> `r2_live`
