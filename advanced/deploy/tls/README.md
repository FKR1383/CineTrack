Generated TLS material is deliberately not committed. Run `./scripts/generate_tls.sh`.
The script creates a private CA, an IP-SAN server certificate, and `fingerprint.sha256` for Flutter certificate pinning. Never distribute `ca.key` or `server.key`.
