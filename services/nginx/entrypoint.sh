#!/bin/sh
set -e

# Optional: write TLS certs from env vars (overrides baked-in certs)
[ -n "$TLS_CERT" ] && printf '%s' "$TLS_CERT" > /etc/nginx/certs/tls.crt
[ -n "$TLS_KEY" ]  && printf '%s' "$TLS_KEY"  > /etc/nginx/certs/tls.key

# Substitute backend hostnames into the config template
envsubst '${WEB_HOST} ${API_HOST} ${BATCH_HOST}' \
  < /etc/nginx/conf.d/bucketeer.conf.template \
  > /etc/nginx/conf.d/bucketeer.conf

exec nginx -g 'daemon off;'
