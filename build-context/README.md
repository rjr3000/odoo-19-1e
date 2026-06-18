# Enterprise zip (baked into Docker image)

`build-context/enterprise-addons.zip` is copied into the image at build time and unpacked to `/opt/odoo/enterprise`. **No release URL. No runtime fetch.**

Refresh from a sibling repo:

```bash
cp ../odoo-monolith-1/app/odoo-src/odoo/addons-enterprise/enterprise-addons.zip build-context/
# or: ../odoo-19-all/addons-enterprise/enterprise-addons.zip
```

Local Docker build (copies zip automatically):

```bash
bash build.sh
```

Railway builds from git — commit the zip via Git LFS after refresh.
