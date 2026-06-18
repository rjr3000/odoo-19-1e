# r2-test — RETIRED

> **Retired 2026-06-16.** Use **`r2-dev`** (dev1 / `dev.odoo.ink`) and branch previews (`r2-pr-<slug>.odoo.ink`) instead. Railway env may still exist until operator deletes it.

# r2-test — Railway `odoo-19-r2` environment **test** (legacy)

| Item | Value |
|------|--------|
| Environment | **test** (`b11ad2f0-5c54-4f42-b49b-9a4c0db35b6b`) |
| Postgres service | `odoo-db-1` |
| Odoo service | `odoo-app-1` |
| DB | `r2_test` |
| Public URL | https://r2-test.up.railway.app |
| Custom URL | https://test.odoo.ink |
| Railway target port | **8080** (`r2-test` Networking; Odoo edge) |
| Bus URL (optional) | second domain on **8072** if longpoll is split out |
| Internal Postgres | `odoo-db-1.railway.internal:5432` (not public) |

## Deploy

```
ADDONS_GIT_REPO=rjr3000/odoo-19-all
ADDONS_GIT_REF=<test branch sha>
CONFIG_PROFILE=r2-test
ODOO_DB=r2_test
PGHOST=odoo-db-1.railway.internal
PGPORT=5432
```

Promotion path: feature PR merges into git branch **`test`** → Railway **`test`** env deploys addon overlay against DB **`r2_test`**.

Factory image refresh:

```bash
bash servers/railway/odoo-19-r2-dev-template/scripts/deploy-from-template.sh env test
```

## Config

- `odoo.conf.snippet` — `http_port = 8069`, `gevent_port = 8072`, `proxy_mode = True`
- `init-modules.txt` — integration module seed (align with test policy)

## Stack row

`02_apps-1.csv` → `r2_test`
