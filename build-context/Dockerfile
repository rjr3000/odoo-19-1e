# odoo-19-1e — standard Odoo 19.0 CE + enterprise (Railway git build).
# Enterprise zip fetched at build from GitHub Release (GH_ADDONS_TOKEN build arg).
# Neon Postgres at runtime via ODOO_DATABASE_* env vars.

FROM odoo:19.0

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/odoo/enterprise /mnt/extra-addons \
    && chown -R odoo:odoo /opt/odoo /mnt/extra-addons

ARG GH_ADDONS_TOKEN=""
ARG ENTERPRISE_ZIP_URL="https://github.com/rjr3000/odoo-19-all/releases/download/enterprise-latest/enterprise-addons.zip"
COPY unpack-enterprise-overlay.sh /usr/local/bin/unpack-enterprise-overlay.sh

RUN chmod +x /usr/local/bin/unpack-enterprise-overlay.sh \
 && set -e \
 && if [ -n "$GH_ADDONS_TOKEN" ]; then \
      curl -fsSL -H "Authorization: Bearer ${GH_ADDONS_TOKEN}" \
        -o /tmp/enterprise-addons.zip "$ENTERPRISE_ZIP_URL"; \
    else \
      curl -fsSL -o /tmp/enterprise-addons.zip "$ENTERPRISE_ZIP_URL"; \
    fi \
 && ODOO_PATH_ENTERPRISE=/opt/odoo/enterprise ENTERPRISE_ZIP_PATH=/tmp/enterprise-addons.zip \
    /usr/local/bin/unpack-enterprise-overlay.sh \
 && rm -f /tmp/enterprise-addons.zip \
 && if [ -f /opt/odoo/enterprise/requirements.txt ]; then \
      pip install --break-system-packages --no-cache-dir --ignore-installed \
        -r /opt/odoo/enterprise/requirements.txt; \
    fi \
 && if [ -f /opt/odoo/enterprise/ai_auto_install/__manifest__.py ]; then \
      sed -i "s/'auto_install': True/'auto_install': False/" \
        /opt/odoo/enterprise/ai_auto_install/__manifest__.py; \
    fi \
 && chown -R odoo:odoo /opt/odoo/enterprise

ENV ODOO_ADDONS_PATH=/usr/lib/python3/dist-packages/odoo/addons,/opt/odoo/enterprise,/mnt/extra-addons

LABEL org.opencontainers.image.title="odoo-19-1e" \
      org.opencontainers.image.description="Odoo 19.0 CE + enterprise (/opt/odoo/enterprise); Neon Railway git build"

USER odoo
