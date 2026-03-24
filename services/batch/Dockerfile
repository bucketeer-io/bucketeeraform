ARG BUCKETEER_VERSION=v2.2.0
FROM ghcr.io/bucketeer-io/bucketeer-batch:${BUCKETEER_VERSION} AS upstream
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates netcat-openbsd socat && rm -rf /var/lib/apt/lists/*
COPY --from=upstream /usr/local/bin/batch /usr/local/bin/bucketeer-batch
# Bake certs (context = repo root)
RUN mkdir -p /usr/local/certs/service /usr/local/service-token /usr/local/oauth-key
COPY certs/tls.crt            /usr/local/certs/service/tls.crt
COPY certs/tls.key            /usr/local/certs/service/tls.key
COPY certs/service-token      /usr/local/service-token/token
COPY certs/oauth-public.pem   /usr/local/oauth-key/public.pem
COPY flyio/resolve-hosts.sh /resolve-hosts.sh
COPY services/batch/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /resolve-hosts.sh /usr/local/bin/bucketeer-batch
ENTRYPOINT ["/entrypoint.sh"]
