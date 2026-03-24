ARG BUCKETEER_VERSION=v2.2.0
FROM ghcr.io/bucketeer-io/bucketeer-subscriber:${BUCKETEER_VERSION} AS upstream
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=upstream /usr/local/bin/subscriber /usr/local/bin/bucketeer-subscriber
# Bake certs (context = repo root)
RUN mkdir -p /usr/local/certs/service /usr/local/service-token /usr/local/oauth-key
COPY certs/tls.crt            /usr/local/certs/service/tls.crt
COPY certs/tls.key            /usr/local/certs/service/tls.key
COPY certs/service-token      /usr/local/service-token/token
COPY certs/oauth-public.pem   /usr/local/oauth-key/public.pem
# Bundle subscriber config (config/ at repo root)
COPY config/subscriber-config /usr/local/conf
COPY config/email-config.json /usr/local/email-config/email-config.json
COPY services/subscriber/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/bucketeer-subscriber
ENTRYPOINT ["/entrypoint.sh"]
