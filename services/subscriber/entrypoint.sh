#!/bin/sh
set -e
mkdir -p /usr/local/certs/service /usr/local/service-token /usr/local/oauth-key
[ -n "$TLS_CERT" ]       && printf '%s' "$TLS_CERT"       > /usr/local/certs/service/tls.crt
[ -n "$TLS_KEY" ]        && printf '%s' "$TLS_KEY"        > /usr/local/certs/service/tls.key
[ -n "$SERVICE_TOKEN" ]  && printf '%s' "$SERVICE_TOKEN"  > /usr/local/service-token/token
[ -n "$OAUTH_PUBLIC_KEY" ] && printf '%s' "$OAUTH_PUBLIC_KEY" > /usr/local/oauth-key/public.pem
# Config files bake "redis:6379"; substitute with actual Redis address from env (e.g. ElastiCache)
REDIS_ADDR="${BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_ADDR:-redis:6379}"
for f in /usr/local/conf/*.json; do [ -f "$f" ] && sed -i "s|redis:6379|$REDIS_ADDR|g" "$f"; done
exec /usr/local/bin/bucketeer-subscriber server
