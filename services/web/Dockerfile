ARG BUCKETEER_VERSION=v2.2.0
FROM ghcr.io/bucketeer-io/bucketeer-web:${BUCKETEER_VERSION} AS upstream
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates netcat-openbsd socat && rm -rf /var/lib/apt/lists/*
COPY --from=upstream /usr/local/bin/web /usr/local/bin/bucketeer-web
# Bake certs so /usr/local/certs/service, service-token, oauth-key exist (context = repo root)
RUN mkdir -p /usr/local/certs/service /usr/local/service-token /usr/local/oauth-key
COPY certs/tls.crt            /usr/local/certs/service/tls.crt
COPY certs/tls.key            /usr/local/certs/service/tls.key
COPY certs/service-token      /usr/local/service-token/token
COPY certs/oauth-public.pem   /usr/local/oauth-key/public.pem
COPY certs/oauth-private.pem  /usr/local/oauth-key/private.pem
# Bundle config (same paths as compose; config/ at repo root)
COPY config/oauth-config.json      /usr/local/oauth-config/oauth-config.json
COPY config/email-config.json      /usr/local/email-config/email-config.json
COPY config/datawarehouse.yaml     /usr/local/datawarehouse-config/datawarehouse.yaml
COPY config/static-files           /usr/local/static
COPY flyio/resolve-hosts.sh /resolve-hosts.sh
COPY services/web/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /resolve-hosts.sh /usr/local/bin/bucketeer-web
ENTRYPOINT ["/entrypoint.sh"]
