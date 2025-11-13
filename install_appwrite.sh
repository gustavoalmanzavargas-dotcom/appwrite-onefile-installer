#!/usr/bin/env bash
# Appwrite on LXC (single script) — install / update / uninstall
# Works in Proxmox LXC (Ubuntu/Debian). Handles:
# - Docker + compose
# - Appwrite 1.6.x compose
# - Traefik v3 override with DOCKER_API_VERSION=1.46
# - Clean .env (no quotes) with your domain + SMTP

set -euo pipefail

ACTION=""
CTID=""
APPWRITE_DIR="/opt/appwrite/appwrite"

APP_DOMAIN="localhost"
APP_DOMAIN_TARGET=""
EMAIL_NAME="CeyeberKeep"
EMAIL_ADDR="no-reply@ceyeberkeep.com"

SMTP_HOST="mail.ceyeberkeep.com"
SMTP_PORT="587"
SMTP_SECURE="tls"   # tls (STARTTLS) or none
SMTP_USER="no-reply@ceyeberkeep.com"
SMTP_PASS=""

log() { printf "\033[1;36m==>\033[0m %s\n" "$*"; }
err() { printf "\033[1;31mERR:\033[0m %s\n" "$*" >&2; }
die() { err "$1"; exit 1; }
need_root() { [[ $(id -u) -eq 0 ]] || die "Run as root (sudo)."; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|update|uninstall) ACTION="$1"; shift ;;
    --ctid) CTID="$2"; shift 2 ;;
    --dir) APPWRITE_DIR="$2"; shift 2 ;;
    --domain) APP_DOMAIN="$2"; APP_DOMAIN_TARGET="$2"; shift 2 ;;
    --domain-target) APP_DOMAIN_TARGET="$2"; shift 2 ;;
    --email-name) EMAIL_NAME="$2"; shift 2 ;;
    --email-address) EMAIL_ADDR="$2"; shift 2 ;;
    --smtp-host) SMTP_HOST="$2"; shift 2 ;;
    --smtp-port) SMTP_PORT="$2"; shift 2 ;;
    --smtp-secure) SMTP_SECURE="$2"; shift 2 ;;
    --smtp-username) SMTP_USER="$2"; shift 2 ;;
    --smtp-password) SMTP_PASS="$2"; shift 2 ;;
    --purge) PURGE="1"; shift ;;
    -h|--help) ACTION="help"; shift ;;
    *) die "Unknown arg: $1" ;;
  esac
done

APP_DOMAIN_TARGET="${APP_DOMAIN_TARGET:-$APP_DOMAIN}"
PURGE="${PURGE:-0}"

usage() {
cat <<USAGE
Appwrite one-file installer (install / update / uninstall)

Actions:
  install     Install Docker + Appwrite stack (Traefik v3 override) and write .env
  update      Pull latest images and recreate containers
  uninstall   Stop stack; add --purge to remove volumes and files
USAGE
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker
    return
  fi
  log "Installing Docker Engine + compose plugin…"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(
    . /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl start docker
}

fetch_compose() {
  log "Preparing directory: $APPWRITE_DIR"
  mkdir -p "$APPWRITE_DIR"
  cd "$APPWRITE_DIR"
  if [[ ! -f docker-compose.yml ]]; then
    log "Fetching Appwrite docker-compose.yml (1.6.x)…"
    set +e
    curl -fsSL https://raw.githubusercontent.com/appwrite/appwrite/1.6.2/docker-compose.yml -o docker-compose.yml
    C1=$?
    if [[ $C1 -ne 0 ]]; then
      curl -fsSL https://raw.githubusercontent.com/appwrite/appwrite/1.6/docker-compose.yml -o docker-compose.yml || {
        die "Failed to download docker-compose.yml"; }
    fi
    set -e
  else
    log "docker-compose.yml already present — keeping it."
  fi
}

write_env() {
  log "Writing .env"
  cat > .env <<ENVEOF
_APP_ENV=production
_APP_OPENSSL_KEY_V1=$(openssl rand -hex 32)

_APP_DOMAIN=$APP_DOMAIN
_APP_DOMAIN_TARGET=$APP_DOMAIN_TARGET

_APP_EMAIL_NAME=$EMAIL_NAME
_APP_EMAIL_ADDRESS=$EMAIL_ADDR

_APP_SMTP_HOST=$SMTP_HOST
_APP_SMTP_PORT=$SMTP_PORT
_APP_SMTP_SECURE=$SMTP_SECURE
_APP_SMTP_USERNAME=$SMTP_USER
_APP_SMTP_PASSWORD=$SMTP_PASS
ENVEOF
}

write_override() {
  log "Writing docker-compose.override.yml (Traefik v3 + Docker API fix)"
  cat > docker-compose.override.yml <<'OVR'
services:
  traefik:
    image: traefik:v3.1
    environment:
      - DOCKER_HOST=unix:///var/run/docker.sock
      - DOCKER_API_VERSION=1.46
    command:
      - --providers.docker=true
      - --providers.docker.endpoint=unix:///var/run/docker.sock
      - --providers.docker.exposedbydefault=false
      - --providers.docker.network=appwrite
      - --entrypoints.appwrite_web.address=:80
      - --entrypoints.appwrite_websecure.address=:443
      - --api.dashboard=false
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "80:80"
      - "443:443"
OVR
}

bring_up() {
  log "Starting stack… (docker compose up -d)"
  docker compose pull
  docker compose up -d
  log "Quick health check"
  sleep 3
  docker logs --since=60s appwrite-traefik 2>/dev/null | egrep -i "entrypoints|router|rule|error|warning|version" || true
  curl -sI "http://127.0.0.1/console" | sed -n '1,5p' || true
  cat <<NOTE

✅ Appwrite is up.

Console:
  • http://$APP_DOMAIN/console

SMTP (as written to .env):
  host=$SMTP_HOST port=$SMTP_PORT secure=$SMTP_SECURE user=$SMTP_USER

Make your "super admin":
  • Console → Settings → Members → Invite "admin@ceyeberkeep.com" with Role **Owner**

NOTE
}

do_install()  { need_root; install_docker_if_needed; fetch_compose; write_env; write_override; bring_up; }
do_update()   { need_root; cd "$APPWRITE_DIR" || die "No such dir: $APPWRITE_DIR"; log "Updating…"; docker compose pull; docker compose up -d; log "Done."; }
do_uninstall(){ need_root; cd "$APPWRITE_DIR" || { log "Nothing to remove at $APPWRITE_DIR"; exit 0; }; log "Stopping…"; docker compose down || true; if [[ "${PURGE:-0}" == "1" ]]; then log "Purging volumes + files…"; docker volume rm -f appwrite-config appwrite-certificates || true; rm -rf "$APPWRITE_DIR"; log "Purged."; else log "Stopped. Data preserved."; fi; }

case "${ACTION:-}" in
  install)   do_install ;;
  update)    do_update ;;
  uninstall) do_uninstall ;;
  *)         usage ;;
esac
