#!/bin/sh
set -e
mkdir -p /usr/local/certs/service /usr/local/service-token /usr/local/oauth-key
[ -n "$TLS_CERT" ]       && printf '%s' "$TLS_CERT"       > /usr/local/certs/service/tls.crt
[ -n "$TLS_KEY" ]        && printf '%s' "$TLS_KEY"        > /usr/local/certs/service/tls.key
[ -n "$SERVICE_TOKEN" ]  && printf '%s' "$SERVICE_TOKEN"  > /usr/local/service-token/token
[ -n "$OAUTH_PUBLIC_KEY" ]  && printf '%s' "$OAUTH_PUBLIC_KEY"  > /usr/local/oauth-key/public.pem
[ -n "$OAUTH_PRIVATE_KEY" ] && printf '%s' "$OAUTH_PRIVATE_KEY" > /usr/local/oauth-key/private.pem
exec /usr/local/bin/bucketeer-web server
