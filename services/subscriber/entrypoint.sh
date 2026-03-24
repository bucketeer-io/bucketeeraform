#!/bin/sh
set -e
mkdir -p /usr/local/certs/service /usr/local/service-token /usr/local/oauth-key
[ -n "$TLS_CERT" ]       && printf '%s' "$TLS_CERT"       > /usr/local/certs/service/tls.crt
[ -n "$TLS_KEY" ]        && printf '%s' "$TLS_KEY"        > /usr/local/certs/service/tls.key
[ -n "$SERVICE_TOKEN" ]  && printf '%s' "$SERVICE_TOKEN"  > /usr/local/service-token/token
[ -n "$OAUTH_PUBLIC_KEY" ] && printf '%s' "$OAUTH_PUBLIC_KEY" > /usr/local/oauth-key/public.pem

. /resolve-hosts.sh

REDIS_HOST=$(echo "${BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_ADDR}" | cut -d: -f1)
REDIS_PORT=$(echo "${BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_ADDR}" | cut -d: -f2)

cat > /tmp/redis-auth-proxy.sh << 'PROXYEOF'
#!/bin/bash
exec 3<>/dev/tcp/${REDIS_UPSTREAM_HOST}/${REDIS_UPSTREAM_PORT}
printf "AUTH %s\r\n" "${REDIS_UPSTREAM_PASSWORD}" >&3
read -r _ <&3
cat <&3 &
BG=$!
trap "kill $BG 2>/dev/null; exec 3>&-" EXIT
cat >&3
PROXYEOF
chmod +x /tmp/redis-auth-proxy.sh

export REDIS_UPSTREAM_HOST="${REDIS_HOST}"
export REDIS_UPSTREAM_PORT="${REDIS_PORT}"
export REDIS_UPSTREAM_PASSWORD="${BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_PASSWORD}"

socat TCP-LISTEN:16379,fork,reuseaddr,bind=127.0.0.1 EXEC:"bash /tmp/redis-auth-proxy.sh" &
sleep 0.5

export BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_ADDR="127.0.0.1:16379"
export BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_ADDR="127.0.0.1:16379"
export BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_ADDR="127.0.0.1:16379"

# Config files bake "redis:6379"; substitute with proxy address after proxy is up
for f in /usr/local/conf/*.json; do [ -f "$f" ] && sed -i "s|redis:6379|127.0.0.1:16379|g" "$f"; done

exec /usr/local/bin/bucketeer-subscriber server
