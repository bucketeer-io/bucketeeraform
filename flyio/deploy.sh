#!/bin/bash
# Full Bucketeer deployment to Fly.io.
# Run from the repo root: bash flyio/deploy.sh
set -e
export FLYCTL_NO_UPDATE_CHECK=1
export FLY_NO_UPDATE_CHECK=1

source flyio/config.env

P="${APP_PREFIX}"
CERTS="${CERTS_DIR}"
REDIS_DB_NAME="${P}-redis"

log() { echo ""; echo "==> $*"; }

# Start any stopped/suspended machines so fly deploy can update them.
ensure_machines_running() {
  local app="$1"
  local machines
  machines=$(fly machines list -a "${app}" 2>/dev/null || true)
  echo "${machines}" | while IFS= read -r line; do
    local mid state
    mid=$(echo "${line}" | awk '{print $1}')
    state=$(echo "${line}" | awk '{print $3}')
    case "${state}" in
      stopped|suspended)
        echo "  Starting ${state} machine ${mid} in ${app}..."
        fly machines start "${mid}" -a "${app}" 2>/dev/null || \
          (echo "  Could not start ${mid}, destroying so deploy can recreate..." && \
           fly machines destroy "${mid}" -a "${app}" --force 2>/dev/null || true)
        ;;
    esac
  done
}

# ── 1. Create apps (skip if already exists) ──────────────────────────────────
log "Creating apps..."
existing_apps=$(fly apps list 2>/dev/null || true)
for svc in mysql httpstan migration web api batch subscriber nginx batch-cron; do
  app="${P}-${svc}"
  if echo "${existing_apps}" | grep -q "${app}"; then
    echo "  ${app} already exists"
  else
    fly app create "${app}" --org personal
  fi
done

# ── 2. Allocate public IPs for nginx and api ─────────────────────────────────
for ip_app in "${P}-nginx" "${P}-api"; do
  log "Allocating IPs for ${ip_app}..."
  app_ips=$(fly ips list -a "${ip_app}" 2>/dev/null || true)
  if echo "${app_ips}" | grep -q "v4"; then
    echo "  IPv4 already allocated"
  else
    fly ips allocate-v4 --yes -a "${ip_app}"
  fi
  if echo "${app_ips}" | grep -q "v6"; then
    echo "  IPv6 already allocated"
  else
    fly ips allocate-v6 -a "${ip_app}"
  fi
done

# ── 2b. Provision Upstash Redis (via Fly.io integration) ──────────────────────
log "Provisioning Upstash Redis..."
redis_list=$(fly redis list 2>/dev/null || true)
if echo "${redis_list}" | grep -q "${REDIS_DB_NAME}"; then
  echo "  ${REDIS_DB_NAME} already exists"
else
  fly redis create \
    --name "${REDIS_DB_NAME}" \
    --region "${REGION}" \
    --no-replicas \
    --disable-eviction \
    --enable-prodpack=false \
    --plan "Pay-as-you-go" \
    -o personal
fi

log "Reading Redis credentials..."
redis_status=$(fly redis status "${REDIS_DB_NAME}" 2>/dev/null || true)
REDIS_PRIVATE_URL=$(echo "${redis_status}" | grep -i "private url" | awk '{print $NF}')
if [ -z "${REDIS_PRIVATE_URL}" ]; then
  echo "  ERROR: Could not read Redis credentials from 'fly redis status ${REDIS_DB_NAME}'" >&2
  exit 1
fi
REDIS_PASSWORD=$(echo "${REDIS_PRIVATE_URL}" | sed 's|redis://[^:]*:\([^@]*\)@.*|\1|')
REDIS_ADDR=$(echo "${REDIS_PRIVATE_URL}" | sed 's|redis://[^@]*@||')
echo "  Redis addr: ${REDIS_ADDR}"

# ── 3. Create volumes (skip if already exists) ───────────────────────────────
log "Creating MySQL volume..."
existing_vols=$(fly vol list --app "${P}-mysql" 2>/dev/null || true)
if echo "${existing_vols}" | grep -q "mysql_data"; then
  echo "  mysql_data already exists"
else
  fly vol create mysql_data --app "${P}-mysql" --size 1 -r "${REGION}" --yes
fi

# ── 4. Set secrets ────────────────────────────────────────────────────────────
if [ ! -f "${CERTS}/tls.key" ] || [ ! -f "${CERTS}/tls.crt" ] \
  || [ ! -f "${CERTS}/oauth-private.pem" ] || [ ! -f "${CERTS}/oauth-public.pem" ] \
  || [ ! -f "${CERTS}/service-token" ]; then
  log "Generating example certs..."
  bash certs/generate.sh "${CERTS}"
fi
# Dockerfiles copy the repository certs/ directory. When CERTS_DIR points
# somewhere else, the image must still receive the same files the Fly secrets use.
repo_certs="$(cd "$(dirname "$0")/.." && pwd)/certs"
certs_abs="$(cd "${CERTS}" && pwd)"
if [ "${certs_abs}" != "${repo_certs}" ]; then
  mkdir -p "${repo_certs}"
  cp "${CERTS}/tls.crt" "${CERTS}/tls.key" "${CERTS}/oauth-public.pem" \
    "${CERTS}/oauth-private.pem" "${CERTS}/service-token" "${repo_certs}/"
  chmod 600 "${repo_certs}/tls.key" "${repo_certs}/oauth-private.pem" "${repo_certs}/service-token"
fi
TLS_CERT=$(cat "${CERTS}/tls.crt")
TLS_KEY=$(cat "${CERTS}/tls.key")
SERVICE_TOKEN=$(cat "${CERTS}/service-token")
OAUTH_PUBLIC_KEY=$(cat "${CERTS}/oauth-public.pem")
OAUTH_PRIVATE_KEY=$(cat "${CERTS}/oauth-private.pem")

log "Setting secrets for mysql..."
fly secrets set \
  MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
  MYSQL_PASSWORD="${MYSQL_PASSWORD}" \
  -a "${P}-mysql"

log "Setting secrets for web..."
fly secrets set \
  BUCKETEER_WEB_MYSQL_PASS="${MYSQL_PASSWORD}" \
  BUCKETEER_WEB_PERSISTENT_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_WEB_PERSISTENT_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_WEB_NON_PERSISTENT_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_WEB_NON_PERSISTENT_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_WEB_PUBSUB_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_WEB_PUBSUB_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  TLS_CERT="${TLS_CERT}" TLS_KEY="${TLS_KEY}" \
  SERVICE_TOKEN="${SERVICE_TOKEN}" \
  OAUTH_PUBLIC_KEY="${OAUTH_PUBLIC_KEY}" \
  OAUTH_PRIVATE_KEY="${OAUTH_PRIVATE_KEY}" \
  -a "${P}-web"

log "Setting secrets for api..."
fly secrets set \
  BUCKETEER_API_MYSQL_PASS="${MYSQL_PASSWORD}" \
  BUCKETEER_API_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_API_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_API_PUBSUB_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_API_PUBSUB_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  TLS_CERT="${TLS_CERT}" TLS_KEY="${TLS_KEY}" \
  SERVICE_TOKEN="${SERVICE_TOKEN}" \
  -a "${P}-api"

log "Setting secrets for batch..."
fly secrets set \
  BUCKETEER_BATCH_MYSQL_PASS="${MYSQL_PASSWORD}" \
  BUCKETEER_BATCH_PERSISTENT_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_BATCH_PERSISTENT_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_BATCH_NON_PERSISTENT_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_BATCH_NON_PERSISTENT_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_BATCH_PUBSUB_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_BATCH_PUBSUB_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  TLS_CERT="${TLS_CERT}" TLS_KEY="${TLS_KEY}" \
  SERVICE_TOKEN="${SERVICE_TOKEN}" \
  OAUTH_PUBLIC_KEY="${OAUTH_PUBLIC_KEY}" \
  -a "${P}-batch"

log "Setting secrets for subscriber..."
fly secrets set \
  BUCKETEER_SUBSCRIBER_MYSQL_PASS="${MYSQL_PASSWORD}" \
  BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_SUBSCRIBER_PERSISTENT_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_SUBSCRIBER_NON_PERSISTENT_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_ADDR="${REDIS_ADDR}" \
  BUCKETEER_SUBSCRIBER_PUBSUB_REDIS_PASSWORD="${REDIS_PASSWORD}" \
  TLS_CERT="${TLS_CERT}" TLS_KEY="${TLS_KEY}" \
  SERVICE_TOKEN="${SERVICE_TOKEN}" \
  OAUTH_PUBLIC_KEY="${OAUTH_PUBLIC_KEY}" \
  -a "${P}-subscriber"

log "Setting secrets for nginx..."
fly secrets set \
  TLS_CERT="${TLS_CERT}" TLS_KEY="${TLS_KEY}" \
  -a "${P}-nginx"

log "Setting secrets for batch-cron..."
fly secrets set \
  TLS_CERT="${TLS_CERT}" SERVICE_TOKEN="${SERVICE_TOKEN}" \
  -a "${P}-batch-cron"

# ── 5. Build and push custom images ───────────────────────────────────────────
log "Building and pushing images (BUCKETEER_VERSION=${BUCKETEER_VERSION})..."
for svc in mysql web api batch subscriber nginx batch-cron; do
  image="registry.fly.io/${P}-${svc}:latest"
  echo "  Building ${image}..."
  if [ "${svc}" = "nginx" ]; then
    docker build --platform linux/amd64 --build-arg NGINX_CONF=config/nginx/bucketeer-flyio.conf --build-arg BUCKETEER_VERSION="${BUCKETEER_VERSION}" -t "${image}" -f "services/${svc}/Dockerfile" .
  else
    docker build --platform linux/amd64 --build-arg BUCKETEER_VERSION="${BUCKETEER_VERSION}" -t "${image}" -f "services/${svc}/Dockerfile" .
  fi
  fly auth docker 2>/dev/null
  docker push "${image}"
done

# ── 6. Deploy MySQL and httpstan ──────────────────────────────────────────────
log "Deploying mysql..."
ensure_machines_running "${P}-mysql"
fly deploy --config flyio/mysql/fly.toml --app "${P}-mysql" --ha=false \
  --image "registry.fly.io/${P}-mysql:${BUCKETEER_VERSION}"

log "Waiting for MySQL TCP port 3306 to be ready..."
for i in $(seq 1 60); do
  if fly ssh console -a "${P}-mysql" -C "grep -q 0CEA /proc/net/tcp6" 2>/dev/null; then
    echo "  MySQL TCP port 3306 is open"
    break
  fi
  if [ "${i}" -eq 60 ]; then
    echo "  ERROR: MySQL TCP port did not open in time" >&2
    exit 1
  fi
  echo "  Waiting for MySQL init to finish... (${i}/60)"
  sleep 5
done

log "Ensuring MySQL user and database exist..."
fly ssh console -a "${P}-mysql" -C "mysql -h localhost -uroot -p'${MYSQL_ROOT_PASSWORD}' -e \"\
  CREATE DATABASE IF NOT EXISTS bucketeer; \
  CREATE USER IF NOT EXISTS 'bucketeer'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}'; \
  GRANT ALL PRIVILEGES ON bucketeer.* TO 'bucketeer'@'%'; \
  FLUSH PRIVILEGES;\"" 2>/dev/null || \
fly ssh console -a "${P}-mysql" -C "mysql -h localhost -uroot --skip-password -e \"\
  CREATE DATABASE IF NOT EXISTS bucketeer; \
  CREATE USER IF NOT EXISTS 'bucketeer'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}'; \
  GRANT ALL PRIVILEGES ON bucketeer.* TO 'bucketeer'@'%'; \
  ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; \
  FLUSH PRIVILEGES;\""

log "Deploying httpstan..."
ensure_machines_running "${P}-httpstan"
fly deploy --config flyio/httpstan/fly.toml --app "${P}-httpstan" --ha=false \
  --image "ghcr.io/bucketeer-io/bucketeer-httpstan:0.0.1"

# ── 7. Run database migration (one-shot) ──────────────────────────────────────
# Atlas needs to know which migrations have already been applied.  When the
# atlas_schema_revisions table is missing or empty (first deploy, or previous
# migration failed before recording anything), we use --baseline to tell Atlas
# the initialization migration (20240626022133) is already applied.
log "Checking migration state..."
has_revisions=$(fly ssh console -a "${P}-mysql" -C "mysql -h localhost -uroot -p'${MYSQL_ROOT_PASSWORD}' bucketeer -N -B -e \"\
  SELECT COUNT(*) FROM atlas_schema_revisions;\"" 2>/dev/null \
  | tail -1 | tr -d '[:space:]' || echo "0")

BASELINE_FLAG=""
if [ "${has_revisions}" = "0" ] || [ -z "${has_revisions}" ]; then
  echo "  No migration history — will use --baseline 20240626022133"
  fly ssh console -a "${P}-mysql" -C "mysql -h localhost -uroot -p'${MYSQL_ROOT_PASSWORD}' bucketeer -e \
    'DROP TABLE IF EXISTS atlas_schema_revisions;'" 2>/dev/null || true
  BASELINE_FLAG="--baseline 20240626022133"
else
  echo "  Found ${has_revisions} applied migrations — atlas will apply incremental"
fi

log "Running database migration..."
fly machine run \
  "ghcr.io/bucketeer-io/bucketeer-migration:${BUCKETEER_VERSION}" \
  --app "${P}-migration" \
  --region "${REGION}" \
  -- migrate apply \
     ${BASELINE_FLAG} \
     -u "mysql://bucketeer:${MYSQL_PASSWORD}@${P}-mysql.internal:3306/bucketeer"

# ── 8. Deploy application services ────────────────────────────────────────────
log "Deploying web..."
ensure_machines_running "${P}-web"
fly deploy --config flyio/web/fly.toml --app "${P}-web" --ha=false \
  --image "registry.fly.io/${P}-web:${BUCKETEER_VERSION}"

log "Deploying api (global)..."
ensure_machines_running "${P}-api"
fly deploy --config flyio/api/fly.toml --app "${P}-api" \
  --image "registry.fly.io/${P}-api:${BUCKETEER_VERSION}"

IFS=',' read -ra API_REGION_LIST <<< "${API_REGIONS:-${REGION}}"
log "Scaling api to ${#API_REGION_LIST[@]} region(s): ${API_REGIONS:-${REGION}}"
SCALE_ARGS=""
for r in "${API_REGION_LIST[@]}"; do
  SCALE_ARGS="${SCALE_ARGS} --region ${r}=1"
done
fly scale count ${SCALE_ARGS} -a "${P}-api" --yes 2>/dev/null || true

log "Deploying batch..."
ensure_machines_running "${P}-batch"
fly deploy --config flyio/batch/fly.toml --app "${P}-batch" --ha=false \
  --image "registry.fly.io/${P}-batch:${BUCKETEER_VERSION}"

log "Deploying subscriber..."
ensure_machines_running "${P}-subscriber"
fly deploy --config flyio/subscriber/fly.toml --app "${P}-subscriber" --ha=false \
  --image "registry.fly.io/${P}-subscriber:${BUCKETEER_VERSION}"

# ── 9. Deploy nginx and batch-cron ────────────────────────────────────────────
log "Deploying nginx..."
ensure_machines_running "${P}-nginx"
fly deploy --config flyio/nginx/fly.toml --app "${P}-nginx" --ha=false \
  --image "registry.fly.io/${P}-nginx:${BUCKETEER_VERSION}"

log "Deploying batch-cron..."
ensure_machines_running "${P}-batch-cron"
fly deploy --config flyio/batch-cron/fly.toml --app "${P}-batch-cron" --ha=false \
  --image "registry.fly.io/${P}-batch-cron:${BUCKETEER_VERSION}"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Done!"
echo "  Nginx (web console): $(fly ips list -a ${P}-nginx | grep v4 | awk '{print $3}')"
echo "  API   (global SDK):  $(fly ips list -a ${P}-api   | grep v4 | awk '{print $3}')"
echo "  API regions:         ${API_REGIONS:-${REGION}}"
