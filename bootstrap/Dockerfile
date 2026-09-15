# purrbrews-bootstrap — serves the node init scripts, SSH public keys and the
# fleet settings (no secrets) to fresh nodes on the LAN.
#
# Build context is the REPO ROOT (see compose.yaml), so init/ can be copied in.
# Keys and settings are never baked into the image: they are bind-mounted from
# bootstrap/data/ at runtime. The root .dockerignore keeps them out of the
# build context as well.

FROM nginx:1.29.8-alpine

RUN apk add --no-cache openssl \
 && rm -f /etc/nginx/conf.d/default.conf \
 && mkdir -p /srv/www/files /certs

# Scripts served to nodes (snapshot at build time — rebuild after editing init/).
COPY init/purrbrews-init.sh init/purrbrews-mac.sh init/purrbrews-init.env.example /srv/www/files/
COPY init/lib/ /srv/www/files/lib/
COPY bootstrap/bootstrap.sh /srv/www/bootstrap.sh

COPY bootstrap/nginx.conf /etc/nginx/conf.d/purrbrews.conf
COPY bootstrap/entrypoint.sh /docker-entrypoint.d/40-purrbrews.sh

RUN chmod 755 /docker-entrypoint.d/40-purrbrews.sh \
 && chmod -R a+rX /srv/www \
 && cd /srv/www/files && find . -type f ! -name SHA256SUMS -print | sed 's|^\./||' | sort \
      | xargs sha256sum > SHA256SUMS

EXPOSE 8443
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -q --no-check-certificate -O /dev/null https://127.0.0.1:8443/healthz || exit 1
