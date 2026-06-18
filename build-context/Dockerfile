# odoo-19-1e — Odoo 19.0 CE + enterprise factory image (Railway production mimic).
# Mirrors evoluzion26/odoo-19-app-1 build layers used by odoo-19-live-2-template.
# Enterprise zip is supplied at build time (see ../build.sh) — not committed.
# Custom addons: runtime only via ADDONS_GIT_* (never baked).

FROM odoo:19.0

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gcc \
    libldap2-dev \
    libsasl2-dev \
    locales \
    poppler-utils \
    postgresql-client \
    python3-dev \
    util-linux \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=

RUN mkdir -p /opt/odoo/enterprise \
    /opt/odoo/addons-custom/00_custom_templates \
    /opt/odoo/addons-custom/01_custom_app \
    /opt/odoo/addons-custom/02_custom_theme \
    /mnt/extra-addons \
    && chown -R odoo:odoo /opt/odoo /mnt/extra-addons

COPY enterprise-addons.zip /tmp/enterprise-addons.zip
COPY unpack-enterprise-overlay.sh /usr/local/bin/unpack-enterprise-overlay.sh

RUN chmod +x /usr/local/bin/unpack-enterprise-overlay.sh \
 && ODOO_PATH_ENTERPRISE=/opt/odoo/enterprise ENTERPRISE_ZIP_PATH=/tmp/enterprise-addons.zip \
    /usr/local/bin/unpack-enterprise-overlay.sh \
 && rm -f /tmp/enterprise-addons.zip \
 && if [ -f /opt/odoo/enterprise/requirements.txt ]; then \
      cp /opt/odoo/enterprise/requirements.txt /tmp/enterprise-requirements.txt; \
    else \
      : > /tmp/enterprise-requirements.txt; \
    fi \
 && chown -R odoo:odoo /opt/odoo/enterprise

RUN if [ -f /opt/odoo/enterprise/ai_auto_install/__manifest__.py ]; then \
      sed -i "s/'auto_install': True/'auto_install': False/" \
        /opt/odoo/enterprise/ai_auto_install/__manifest__.py \
      && grep -q "'auto_install': False" /opt/odoo/enterprise/ai_auto_install/__manifest__.py; \
    fi

COPY requirements.txt /tmp/requirements.txt
RUN pip install --break-system-packages --no-cache-dir --ignore-installed -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

RUN if [ -s /tmp/enterprise-requirements.txt ]; then \
        sed -i '/^psycopg2==/d' /tmp/enterprise-requirements.txt; \
        pip install --break-system-packages --no-cache-dir --ignore-installed -r /tmp/enterprise-requirements.txt; \
    else \
        echo "No enterprise requirements file entries; skipping"; \
    fi \
    && rm -f /tmp/enterprise-requirements.txt

RUN cd /tmp \
    && python3 -c "import urllib.request; urllib.request.urlretrieve('https://github.com/odoo/upgrade-util/archive/refs/heads/master.tar.gz', 'upgrade-util.tar.gz')" \
    && tar xzf upgrade-util.tar.gz \
    && SETUPTOOLS_SCM_PRETEND_VERSION=0.0.1 pip install --break-system-packages --no-cache-dir /tmp/upgrade-util-master/ \
    && rm -rf /tmp/upgrade-util*

COPY entrypoint-odoo-bootstrap.sh /usr/local/bin/entrypoint-odoo-app.sh
COPY entrypoint-odoo-app.sh /usr/local/bin/entrypoint-odoo-app.baked
COPY railway-host-profiles/ /opt/railway-host-profiles/

RUN sed -i 's/\r$//' /usr/local/bin/entrypoint-odoo-app.sh /usr/local/bin/entrypoint-odoo-app.baked \
    && chmod +x /usr/local/bin/entrypoint-odoo-app.sh /usr/local/bin/entrypoint-odoo-app.baked \
    && ln -sf /usr/local/bin/entrypoint-odoo-app.sh /usr/local/bin/entrypoint-r2-app.sh \
    && ln -sf /usr/local/bin/entrypoint-odoo-app.baked /usr/local/bin/entrypoint-r2-app.baked \
    && ln -sf odoo-dev /opt/railway-host-profiles/r2-dev \
    && ln -sf odoo-live /opt/railway-host-profiles/r2-live \
    && ln -sf odoo-test /opt/railway-host-profiles/r2-test \
    && mkdir -p /etc/odoo && chown -R odoo:odoo /opt/odoo /etc/odoo

ENV ODOO_ADDONS_PATH=/usr/lib/python3/dist-packages/odoo/addons,/opt/odoo/enterprise,/opt/odoo/addons-custom,/mnt/extra-addons

LABEL org.opencontainers.image.title="odoo-19-1e" \
      org.opencontainers.image.description="Odoo 19.0 + enterprise; factory entrypoint + railway-host-profiles"

WORKDIR /app
RUN mkdir -p /app
USER root
