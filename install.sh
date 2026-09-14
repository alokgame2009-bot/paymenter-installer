#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="/var/www/paymenter"
SERVICE_FILE="/etc/systemd/system/paymenter.service"
NGINX_AVAILABLE="/etc/nginx/sites-available/paymenter.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/paymenter.conf"
INFO_FILE="/root/paymenter-install-info.txt"
BACKUP_DIR="/root/paymenter-installer-backups"
LOG_FILE="/var/log/paymenter-installer.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log(){ echo -e "${BLUE}[$(date '+%F %T')]${NC} $*" | tee -a "$LOG_FILE"; }
ok(){ echo -e "${GREEN}✔${NC} $*" | tee -a "$LOG_FILE"; }
warn(){ echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"; }
die(){ echo -e "${RED}✖${NC} $*" | tee -a "$LOG_FILE"; exit 1; }

trap 'die "Installer failed at line $LINENO. Check $LOG_FILE."' ERR

if [[ $EUID -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

uninstall() {
  require_ubuntu

  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  # If Paymenter already exists, recovery is automatic. No extra confirmation.
  if [[ -e "$APP_DIR" ]]; then
    [[ -f "$APP_DIR/.env" ]] || die "$APP_DIR exists but .env is missing. Remove/repair the incomplete directory before installing."
    DB_PASS="$(grep -E '^DB_PASSWORD=' "$APP_DIR/.env" | head -n1 | cut -d= -f2-)"
    [[ -n "$DB_PASS" ]] || die "Could not read the existing Paymenter DB password from .env."

    prompt_config
    DB_PASS="$(grep -E '^DB_PASSWORD=' "$APP_DIR/.env" | head -n1 | cut -d= -f2-)"
    log "Resuming existing Paymenter installation automatically..."
    chown -R www-data:www-data "$APP_DIR"
    chmod -R 755 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"
    setup_database
  else
    prompt_config
    install_packages
    install_paymenter
    setup_database
  fi

  run_interactive_init
  setup_cron_and_queue
  setup_nginx_http
  setup_ssl
  finalize
}

install

