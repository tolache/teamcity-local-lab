#!/usr/bin/env bash
# Generates this lab's TLS material from the developer's own local mkcert CA:
#
#   certs/docker-host-mkcert-rootCA.crt   -> baked into the TeamCity server/agent images
#   certs/nginx.pem + certs/nginx-key.pem -> served by nginx (MinIO, Garage, LDAPS)
#
# None of it is committed - you generate your own. Re-running is a no-op.
# Pass --force to re-mint regardless.

set -euo pipefail

# Hostnames the nginx certificate is valid for. Adding one here re-mints on the next run.
# Vhost-style S3 needs '*.s3.nginx': a bare '*.nginx' fails hostname verification (see garage.toml).
CERT_HOSTS=(nginx '*.nginx' s3.nginx '*.s3.nginx' localhost 127.0.0.1 ::1 host.docker.internal)
# Re-mint when the certificate is within this many days of expiring.
RENEW_BEFORE_DAYS=30

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CERTS_DIR="$REPO_ROOT/certs"
ROOT_CA_DEST="$CERTS_DIR/docker-host-mkcert-rootCA.crt"
LEAF_CERT="$CERTS_DIR/nginx.pem"
LEAF_KEY="$CERTS_DIR/nginx-key.pem"

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}✔${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
die()  { echo -e "${RED}✘${NC} $*" >&2; exit 1; }

FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force) FORCE=1 ;;
    -h|--help)  echo "Usage: $0 [-f|--force]"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

# --- 1. mkcert ----------------------------------------------------------------------
command -v mkcert >/dev/null 2>&1 \
  || die "mkcert not found. Install mkcert first (see README.md), then re-run this script."

# --- 2. Local CA --------------------------------------------------------------------
# `mkcert -install` adds the CA to the OS (and browser) trust store, which is what makes
# https://localhost:9001 trusted on this machine. It is idempotent, and may prompt for a
# password the first time.
CAROOT="$(mkcert -CAROOT)"
if [ ! -f "$CAROOT/rootCA.pem" ]; then
  warn "No mkcert CA in $CAROOT - running 'mkcert -install' (may prompt for your password)."
  mkcert -install
fi
[ -f "$CAROOT/rootCA.pem" ] || die "mkcert -install did not produce $CAROOT/rootCA.pem"

mkdir -p "$CERTS_DIR"

# --- 3. Root CA copy for the TeamCity image builds ----------------------------------
# Only copied when it actually differs, so re-running does not bust the Docker build cache.
# --force does not apply here: it would report a change that did not happen.
root_ca_changed=0
if ! cmp -s "$CAROOT/rootCA.pem" "$ROOT_CA_DEST"; then
  cp "$CAROOT/rootCA.pem" "$ROOT_CA_DEST"
  root_ca_changed=1
fi

# --- 4. nginx leaf certificate ------------------------------------------------------
# `openssl x509 -text` rather than `-ext`: the latter is unavailable in the LibreSSL that
# ships as /usr/bin/openssl on macOS.
cert_sans() {
  openssl x509 -in "$1" -noout -text | grep -A1 'Subject Alternative Name' | tail -n1
}

leaf_is_current() {
  [ -s "$LEAF_CERT" ] && [ -s "$LEAF_KEY" ] || return 1

  openssl x509 -in "$LEAF_CERT" -noout -checkend $((RENEW_BEFORE_DAYS * 86400)) >/dev/null 2>&1 \
    || return 1

  # Catches "I reinstalled mkcert, so my CA changed but the old leaf is still lying here".
  local issuer ca_subject
  issuer="$(openssl x509 -in "$LEAF_CERT" -noout -issuer)"
  ca_subject="$(openssl x509 -in "$CAROOT/rootCA.pem" -noout -subject)"
  [ "${issuer#issuer=}" = "${ca_subject#subject=}" ] || return 1

  # Catches edits to CERT_HOSTS above. IPv6 literals are skipped: OpenSSL prints ::1 in
  # expanded form (0:0:0:0:0:0:0:1), which would never match and would re-mint every run.
  local sans host
  sans="$(cert_sans "$LEAF_CERT")"
  for host in "${CERT_HOSTS[@]}"; do
    case "$host" in *:*) continue ;; esac
    case "$sans" in *"$host"*) ;; *) return 1 ;; esac
  done
}

leaf_changed=0
if [ "$FORCE" -eq 1 ] || ! leaf_is_current; then
  mkcert -cert-file "$LEAF_CERT" -key-file "$LEAF_KEY" "${CERT_HOSTS[@]}"
  leaf_changed=1
fi

# mkcert writes the key 0600, which nginx's master process reads as root before dropping
# privileges. On rootless or userns-remapped Docker that may need `chmod 644 certs/nginx-key.pem`.

# --- 5. Report ----------------------------------------------------------------------
if [ "$root_ca_changed" -eq 1 ]; then
  info "Wrote $(basename "$ROOT_CA_DEST")"
  warn "Root CA changed - rebuild the images:"
  echo "      docker compose up -d --build teamcity teamcity-agent"
else
  info "Root CA already up to date"
fi

if [ "$leaf_changed" -eq 1 ]; then
  info "Wrote $(basename "$LEAF_CERT") and $(basename "$LEAF_KEY")"
  warn "Certificate changed - recreate nginx:"
  echo "      docker compose up -d --force-recreate nginx"
else
  info "nginx certificate valid until $(openssl x509 -in "$LEAF_CERT" -noout -enddate | cut -d= -f2)"
fi
