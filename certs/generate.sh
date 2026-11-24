#!/usr/bin/env bash
# Generate the example TLS certificate, OAuth signing key, and service token.
# The files are gitignored. Docker builds and deploys read them from certs/.
# Do not commit the files this script writes.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
certs="${root}/certs"
mkdir -p "${certs}"

issuer="${OAUTH_ISSUER:-https://localhost}"
audience="${OAUTH_AUDIENCE:-bucketeer}"
email="${SERVICE_TOKEN_EMAIL:-demo@bucketeer.io}"

echo "Generating TLS certificate..."
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "${certs}/tls.key" \
  -out "${certs}/tls.crt" \
  -days 36500 \
  -subj "/CN=*.bucketeer.io" \
  -addext "subjectAltName=DNS:localhost,DNS:*.bucketeer.io,DNS:*.default.svc.cluster.local,DNS:*.bucketeer.local,DNS:nginx,DNS:web,DNS:api,DNS:batch,DNS:subscriber,DNS:mysql,DNS:redis,DNS:bucketeer-web.internal,DNS:bucketeer-nginx.internal,DNS:bucketeer-api.internal,DNS:bucketeer-batch.internal,DNS:bucketeer-subscriber.internal,DNS:bucketeer-mysql.internal"

echo "Generating OAuth signing key..."
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${certs}/oauth-private.pem"
openssl pkey -in "${certs}/oauth-private.pem" -pubout -out "${certs}/oauth-public.pem"

echo "Signing example service token..."
python3 - "${certs}" "${issuer}" "${audience}" "${email}" <<'PY'
import base64
import json
import subprocess
import sys
from datetime import datetime, timedelta, timezone

certs, issuer, audience, email = sys.argv[1:5]
now = datetime.now(timezone.utc)
exp = now + timedelta(days=365 * 100)

def stamp(value):
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")

def b64(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")

header = b64(json.dumps({"alg": "RS256"}, separators=(",", ":")).encode())
payload = b64(
    json.dumps(
        {
            "iss": issuer,
            "aud": audience,
            "exp": stamp(exp),
            "iat": stamp(now),
            "email": email,
            "is_system_admin": True,
            "is_service_token": True,
            "token_use": "access",
        },
        separators=(",", ":"),
    ).encode()
)
signing_input = f"{header}.{payload}".encode()
signature = subprocess.check_output(
    ["openssl", "dgst", "-sha256", "-sign", f"{certs}/oauth-private.pem"],
    input=signing_input,
)
token_path = f"{certs}/service-token"
with open(token_path, "w", encoding="ascii") as handle:
    handle.write(f"{header}.{payload}.{b64(signature)}\n")
PY

chmod 600 "${certs}/tls.key" "${certs}/oauth-private.pem" "${certs}/service-token"
chmod 644 "${certs}/tls.crt" "${certs}/oauth-public.pem"

python3 - "${certs}" <<'PY'
import base64
import subprocess
import sys
import tempfile

certs = sys.argv[1]
with open(f"{certs}/service-token", encoding="ascii") as handle:
    token = handle.read().strip()
header, payload, signature = token.split(".")
pad = "=" * (-len(signature) % 4)
signature_bytes = base64.urlsafe_b64decode(signature + pad)
with tempfile.TemporaryDirectory() as directory:
    data_path = f"{directory}/data"
    sig_path = f"{directory}/sig"
    with open(data_path, "wb") as handle:
        handle.write(f"{header}.{payload}".encode())
    with open(sig_path, "wb") as handle:
        handle.write(signature_bytes)
    subprocess.check_call(
        [
            "openssl",
            "dgst",
            "-sha256",
            "-verify",
            f"{certs}/oauth-public.pem",
            "-signature",
            sig_path,
            data_path,
        ],
        stdout=subprocess.DEVNULL,
    )
PY

echo "Verified the service token with the new OAuth public key."
echo "Done. SANs:"
openssl x509 -in "${certs}/tls.crt" -noout -ext subjectAltName
