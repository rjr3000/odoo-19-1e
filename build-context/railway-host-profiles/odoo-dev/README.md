# r2-dev — Railway `odoo-19-all` development + PR previews

Git integration branch: **`dev`** — create feature branches and PRs from `dev`, not `main`.

| Item | Value |
|------|--------|
| Environment | **dev** / dev1 (`45594616-f4db-4312-8a72-b8203a91326e`) or branch clone `pr-r2-<branch-slug>` |
| Postgres service | `odoo-db-1` |
| Odoo service | `odoo-app-1` |
| DB | `r2_dev` |
| Public URL | https://r2-dev.up.railway.app |
| Custom URL | https://dev.odoo.ink |
| Railway target port | **8069** (factory `odoo-19-app-1`; script sets `APP_TARGET_PORT`) |
| Bus URL (optional) | second domain on **8072** if longpoll is split out |
| Internal Postgres | `odoo-db-1.railway.internal:5432` (not public) |
| CI | `odoo-19-all/.github/workflows/railway-r2-branch-preview.yml` (push feature branch) |

## Deploy

```
ADDONS_GIT_REPO=rjr3000/odoo-19-all
ADDONS_GIT_REF=<branch sha>
CONFIG_PROFILE=r2-dev
ODOO_DB=r2_dev
```

Branch push clones **dev1 variable profile** (not services) → `pr-r2-<branch-slug>` via `templateDeployV2` on first create, then `ADDONS_GIT_REF` overlay + app redeploy. URL: `https://r2-pr-<branch-slug>.odoo.ink/web/login?db=r2_dev`. See [../../odoo-19-r2-dev-template/docs/TEMPLATE.md](../../odoo-19-r2-dev-template/docs/TEMPLATE.md).

Factory image refresh (operator):

```bash
bash servers/railway/odoo-19-r2-dev-template/scripts/deploy-from-template.sh env dev
```

## Config

Lighter workers in `odoo.conf.snippet` (`http_port = 8069`, `gevent_port = 8072`); minimal `init-modules.txt` for empty dev DB bootstrap.

## Stack row

`02_apps-1.csv` → `r2_dev`
