#!/bin/sh
set -e
mkdir -p /usr/local/certs/service /usr/local/service-token
[ -n "$TLS_CERT" ]      && printf '%s' "$TLS_CERT"      > /usr/local/certs/service/tls.crt
[ -n "$TLS_KEY" ]       && printf '%s' "$TLS_KEY"       > /usr/local/certs/service/tls.key
[ -n "$SERVICE_TOKEN" ] && printf '%s' "$SERVICE_TOKEN" > /usr/local/service-token/token
exec /usr/local/bin/bucketeer-api server
