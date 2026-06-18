# odoo-19-1e — Odoo 19.0 + enterprise baked at /opt/odoo/enterprise (Railway git build).
# Same bake pattern as odoo-19-images/odoo-19-e1: COPY enterprise-addons.zip in build context.
# No release URL, no runtime fetch, no GH_ADDONS_TOKEN.

FROM odoo:19.0

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/odoo/enterprise /mnt/extra-addons \
    && chown -R odoo:odoo /opt/odoo /mnt/extra-addons

COPY enterprise-addons.zip /tmp/enterprise-addons.zip
COPY unpack-enterprise-overlay.sh /usr/local/bin/unpack-enterprise-overlay.sh

RUN chmod +x /usr/local/bin/unpack-enterprise-overlay.sh \
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
      org.opencontainers.image.description="Odoo 19.0 CE + enterprise (/opt/odoo/enterprise); baked zip in image"

USER odoo
