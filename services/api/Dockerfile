ARG BUCKETEER_VERSION=v2.2.0
FROM ghcr.io/bucketeer-io/bucketeer-api:${BUCKETEER_VERSION} AS upstream
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates netcat-openbsd socat && rm -rf /var/lib/apt/lists/*
COPY --from=upstream /usr/local/bin/api /usr/local/bin/bucketeer-api
# Bake certs so /usr/local/certs/service and /usr/local/service-token exist (context = repo root)
RUN mkdir -p /usr/local/certs/service /usr/local/service-token
COPY certs/tls.crt       /usr/local/certs/service/tls.crt
COPY certs/tls.key       /usr/local/certs/service/tls.key
COPY certs/service-token /usr/local/service-token/token
COPY flyio/resolve-hosts.sh /resolve-hosts.sh
COPY services/api/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /resolve-hosts.sh /usr/local/bin/bucketeer-api
ENTRYPOINT ["/entrypoint.sh"]
