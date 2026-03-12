FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/bucketeer-io/bucketeer-api:v2.2.0 /usr/local/bin/api /usr/local/bin/bucketeer-api
# Bake certs so /usr/local/certs/service and /usr/local/service-token exist (context = repo root)
RUN mkdir -p /usr/local/certs/service /usr/local/service-token
COPY certs/tls.crt       /usr/local/certs/service/tls.crt
COPY certs/tls.key       /usr/local/certs/service/tls.key
COPY certs/service-token /usr/local/service-token/token
COPY services/api/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/bucketeer-api
ENTRYPOINT ["/entrypoint.sh"]
