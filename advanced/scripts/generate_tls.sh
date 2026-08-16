#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLS_DIR="${TLS_DIR:-$ROOT_DIR/deploy/tls}"
SERVER_IP="${SERVER_IP:-31.57.118.82}"
DAYS="${TLS_DAYS:-825}"

command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }
mkdir -p "$TLS_DIR"
umask 077

if [[ -e "$TLS_DIR/server.key" || -e "$TLS_DIR/ca.key" ]]; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    echo "TLS keys already exist. Set FORCE=1 to replace them." >&2
    exit 1
  fi
  rm -f "$TLS_DIR"/{ca.key,ca.crt,ca.srl,server.key,server.csr,server.crt,server.ext,fingerprint.sha256}
fi

openssl genrsa -out "$TLS_DIR/ca.key" 4096
openssl req -x509 -new -nodes -key "$TLS_DIR/ca.key" -sha256 -days 3650 \
  -subj "/C=CH/O=CineTrack Educational Project/CN=CineTrack Private CA" \
  -out "$TLS_DIR/ca.crt"

openssl genrsa -out "$TLS_DIR/server.key" 3072
openssl req -new -key "$TLS_DIR/server.key" \
  -subj "/C=CH/O=CineTrack Educational Project/CN=$SERVER_IP" \
  -out "$TLS_DIR/server.csr"

cat > "$TLS_DIR/server.ext" <<EXT
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=IP:$SERVER_IP
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EXT

openssl x509 -req -in "$TLS_DIR/server.csr" -CA "$TLS_DIR/ca.crt" -CAkey "$TLS_DIR/ca.key" \
  -CAcreateserial -out "$TLS_DIR/server.crt" -days "$DAYS" -sha256 -extfile "$TLS_DIR/server.ext"

openssl x509 -in "$TLS_DIR/server.crt" -outform DER \
  | openssl dgst -sha256 -binary \
  | xxd -p -c 256 \
  | tr -d '\n' > "$TLS_DIR/fingerprint.sha256"
printf '\n' >> "$TLS_DIR/fingerprint.sha256"

chmod 600 "$TLS_DIR/ca.key" "$TLS_DIR/server.key"
chmod 644 "$TLS_DIR/ca.crt" "$TLS_DIR/server.crt" "$TLS_DIR/fingerprint.sha256"
rm -f "$TLS_DIR/server.csr" "$TLS_DIR/server.ext" "$TLS_DIR/ca.srl"

echo "TLS certificate generated for IP $SERVER_IP"
echo "Flutter CERT_SHA256=$(cat "$TLS_DIR/fingerprint.sha256")"
echo "Keep ca.key and server.key private."
