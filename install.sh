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

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash install.sh"

menu() {
  clear || true

  # Terminal colors
  RED='\033[38;5;196m'
  ORANGE='\033[38;5;208m'
  YELLOW='\033[38;5;226m'
  GREEN='\033[38;5;46m'
  CYAN='\033[38;5;51m'
  PURPLE='\033[38;5;129m'
  WHITE='\033[1;37m'
  DIM='\033[2;37m'
  NC='\033[0m'

  echo
  echo -e "        ${RED}███████${ORANGE}╗${YELLOW}██${GREEN}╗  ${CYAN}██${PURPLE}╗${RED}███${ORANGE}╗   ${YELLOW}██${GREEN}╗"
  echo -e "        ${ORANGE}██${YELLOW}╔════╝${GREEN}██${CYAN}║  ${PURPLE}██${RED}║${ORANGE}████${YELLOW}╗  ${GREEN}██${CYAN}║"
  echo -e "        ${YELLOW}███████${GREEN}╗${CYAN}████${PURPLE}█╔╝${RED}██╔${ORANGE}██╗ ${YELLOW}██${GREEN}║"
  echo -e "        ${GREEN}╚════${CYAN}██${PURPLE}║${RED}██${ORANGE}╔═${YELLOW}██╗ ${GREEN}██║${CYAN}╚██╗${PURPLE}██${RED}║"
  echo -e "        ${CYAN}██████${PURPLE}█║${RED}██${ORANGE}║  ${YELLOW}██╗${GREEN}██║ ${CYAN}╚███${PURPLE}█╔╝"
  echo -e "        ${PURPLE}╚══════${RED}╝${ORANGE}╚═╝  ${YELLOW}╚═╝${GREEN}╚═╝  ${CYAN}╚═══${PURPLE}╝${NC}"
  echo
  echo -e "                 ${WHITE}S K N${NC}"
  echo -e "          ${CYAN}PAYMENTER INSTALLER${NC}"
  echo -e "       ${DIM}Secure • Fast • Automated${NC}"
  echo
  echo -e "                  ${PURPLE}Made by Zyren${NC}"
  echo
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "   ${GREEN}[1]${NC}  ${WHITE}Install Paymenter${NC}"
  echo -e "        ${DIM}Deploy a complete Paymenter server${NC}"
  echo
  echo -e "   ${ORANGE}[2]${NC}  ${WHITE}Uninstall Paymenter${NC}"
  echo -e "        ${DIM}Safely remove the Paymenter installation${NC}"
  echo
  echo -e "   ${RED}[3]${NC}  ${WHITE}Exit${NC}"
  echo
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  read -rp "   Select an option [1-3]: " choice
  case "$choice" in
    1) install ;;
    2) uninstall ;;
    3) exit 0 ;;
    *) die "Invalid choice." ;;
  esac
}

uninstall() {
  echo
  warn "This removes the Paymenter installation, its Nginx site, service and cron."
  warn "Shared packages such as PHP/MariaDB/Redis/Nginx are NOT removed."
  read -rp "Type UNINSTALL to continue: " confirm
  [[ "$confirm" == "UNINSTALL" ]] || { echo "Cancelled."; exit 0; }

  systemctl disable --now paymenter.service 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  rm -f "$NGINX_ENABLED" "$NGINX_AVAILABLE"
  rm -f /etc/nginx/sites-enabled/default

  crontab -u www-data -l 2>/dev/null | grep -vF "$APP_DIR/artisan schedule:run" | crontab -u www-data - 2>/dev/null || true

  if nginx -t >/dev/null 2>&1; then systemctl reload nginx || true; fi

  if [[ -d "$APP_DIR" ]]; then
    mv "$APP_DIR" "${APP_DIR}.removed.$(date +%Y%m%d%H%M%S)"
  fi

  read -rp "Also drop the Paymenter MariaDB database/user? [y/N]: " dropdb
  if [[ "$dropdb" =~ ^[Yy]$ ]]; then
    mysql <<'SQL'
DROP DATABASE IF EXISTS paymenter;
DROP USER IF EXISTS 'paymenter'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
    ok "Paymenter database/user removed."
  fi

  rm -f "$INFO_FILE"
  systemctl daemon-reload
  ok "Paymenter uninstall completed."
}

require_ubuntu() {
  [[ -r /etc/os-release ]] || die "Cannot detect OS."
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || die "This installer targets Ubuntu 24.04."
}

prompt_config() {
  clear
  echo
  echo "=============================================="
  echo "       SKN PAYMENTER INSTALLER"
  echo "        INSTALLATION DETAILS"
  echo "=============================================="
  echo

  read -rp "Domain: " DOMAIN
  read -rp "Company name: " COMPANY
  read -rp "First name: " ADMIN_FIRST_NAME
  read -rp "Last name: " ADMIN_LAST_NAME
  read -rp "Email address: " ADMIN_EMAIL
  read -rsp "Account password: " ADMIN_PASS
  echo
  read -rp "Account type (admin/user) [admin]: " ACCOUNT_TYPE
  ACCOUNT_TYPE="${ACCOUNT_TYPE,,}"
  [[ "$ACCOUNT_TYPE" == "admin" || "$ACCOUNT_TYPE" == "user" ]] || die "Account type must be admin or user."

  read -rp "Let's Encrypt email: " LE_EMAIL

  ADMIN_NAME="${ADMIN_FIRST_NAME} ${ADMIN_LAST_NAME}"
  ADMIN_USER="${ADMIN_EMAIL%%@*}"

  echo
  echo "=============================================="
  echo "       CONFIRM INSTALLATION DETAILS"
  echo "=============================================="
  echo
  echo "Domain          : $DOMAIN"
  echo "Company name    : $COMPANY"
  echo "First name      : $ADMIN_FIRST_NAME"
  echo "Last name       : $ADMIN_LAST_NAME"
  echo "Email address   : $ADMIN_EMAIL"
  echo "Account username: $ADMIN_USER"
  echo "Account type    : $ACCOUNT_TYPE"
  echo "Let's Encrypt    : $LE_EMAIL"
  echo "Password        : ********"
  echo
  read -rp "Are these details correct? [Y/n]: " CONFIRM
  CONFIRM="${CONFIRM:-Y}"
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || die "Installation cancelled. Please run the installer again."
}

install_packages() {
  log "Installing prerequisites..."
  apt-get update
  apt-get install -y software-properties-common curl apt-transport-https ca-certificates gnupg lsb-release openssl dnsutils composer expect

  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php || true

  curl -fsSL https://downloads.mariadb.com/MariaDB/mariadb_repo_setup \
    | bash -s -- --mariadb-server-version="mariadb-10.11"

  apt-get update
  apt-get install -y \
    php8.3 php8.3-common php8.3-cli php8.3-gd php8.3-mysql php8.3-mbstring \
    php8.3-bcmath php8.3-xml php8.3-fpm php8.3-curl php8.3-zip php8.3-intl \
    php8.3-redis php8.3-imap \
    mariadb-server nginx tar unzip git redis-server certbot python3-certbot-nginx

  systemctl enable --now mariadb redis-server php8.3-fpm nginx
  ok "Packages installed."
}

install_paymenter() {
  [[ ! -e "$APP_DIR" ]] || die "$APP_DIR already exists. Refusing to overwrite an existing installation."

  mkdir -p "$APP_DIR"
  cd "$APP_DIR"

  curl -fL --retry 5 --retry-all-errors \
    -o paymenter.tar.gz \
    https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz

  tar -xzf paymenter.tar.gz
  rm -f paymenter.tar.gz

  chmod -R 755 storage bootstrap/cache
  chown -R www-data:www-data "$APP_DIR"

  if [[ ! -d "$APP_DIR/vendor" ]]; then
    sudo -u www-data composer install --no-dev --optimize-autoloader --no-interaction
  fi

  cp .env.example .env
  chown www-data:www-data .env

  # Configure DB without storing credentials in shell history.
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=paymenter/" .env
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=paymenter/" .env
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
  if ! grep -q '^DB_PASSWORD=' .env; then echo "DB_PASSWORD=${DB_PASS}" >> .env; fi

  sudo -u www-data php artisan key:generate --force
  sudo -u www-data php artisan storage:link || true

  ok "Paymenter files and environment prepared."
}

setup_database() {
  systemctl enable --now mariadb
  for i in {1..30}; do
    if mysqladmin ping --silent >/dev/null 2>&1; then break; fi
    sleep 1
  done
  mysqladmin ping --silent >/dev/null 2>&1 || die "MariaDB did not become ready."

  mysql <<SQL
CREATE DATABASE IF NOT EXISTS paymenter CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'paymenter'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
ALTER USER 'paymenter'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON paymenter.* TO 'paymenter'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

  cd "$APP_DIR"
  sudo -u www-data php artisan migrate --force --seed
  sudo -u www-data php artisan db:seed --class=CustomPropertySeeder
  ok "Database configured and migrations completed."
}

run_interactive_init() {
  cd "$APP_DIR"

  info "Initializing Paymenter with the confirmed details..."

  # Use the exact values already confirmed above.
  # Paymenter CLI remains real/official; no second manual data collection.
  export DOMAIN COMPANY ADMIN_FIRST_NAME ADMIN_LAST_NAME ADMIN_NAME ADMIN_USER ADMIN_EMAIL ADMIN_PASS ACCOUNT_TYPE

  # app:init: feed only the values collected by this installer.
  # Current Paymenter expects application/company information and URL interactively.
  printf '%s\n%s\n' "$COMPANY" "https://${DOMAIN}" |     sudo -u www-data php artisan app:init

  if [[ "$ACCOUNT_TYPE" == "admin" ]]; then
    ADMIN_FLAG="1"
  else
    ADMIN_FLAG="0"
  fi

  # app:user:create: reuse the confirmed account values.
  # Username is derived automatically from the email local-part.
  printf '%s\n%s\n%s\n%s\n%s\n'     "$ADMIN_USER" "$ADMIN_NAME" "$ADMIN_EMAIL" "$ADMIN_PASS" "$ADMIN_FLAG" |     sudo -u www-data php artisan app:user:create

  sudo -u www-data php artisan app:settings:change app_url "https://${DOMAIN}"
}


setup_cron_and_queue() {
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Paymenter Queue Worker
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/php $APP_DIR/artisan queue:work --sleep=3 --tries=3 --timeout=120
Restart=always
RestartSec=5
StartLimitIntervalSec=180
StartLimitBurst=30

[Install]
WantedBy=multi-user.target
EOF

  touch /etc/cron.d/paymenter
  cat > /etc/cron.d/paymenter <<EOF
* * * * * www-data cd $APP_DIR && /usr/bin/php artisan schedule:run >> /dev/null 2>&1
EOF
  chmod 644 /etc/cron.d/paymenter

  systemctl daemon-reload
  systemctl enable --now paymenter.service
  systemctl restart redis-server
  ok "Queue worker and scheduler configured."
}

setup_nginx_http() {
  cat > "$NGINX_AVAILABLE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    root $APP_DIR/public;
    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ ^/index\\.php(/|$) {
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\\.(?!well-known).* {
        deny all;
    }
}
EOF

  ln -sfn "$NGINX_AVAILABLE" "$NGINX_ENABLED"
  rm -f /etc/nginx/sites-enabled/default

  nginx -t
  systemctl restart nginx
}

setup_ssl() {
  echo
  log "Checking DNS for $DOMAIN..."
  SERVER_IP="$(curl -4fsS https://api.ipify.org || true)"
  DNS_IP="$(dig +short A "$DOMAIN" | tail -n1 || true)"

  if [[ -z "$SERVER_IP" || -z "$DNS_IP" || "$SERVER_IP" != "$DNS_IP" ]]; then
    warn "DNS A record does not currently point to this server."
    warn "Server IPv4: ${SERVER_IP:-unknown}"
    warn "DNS IPv4:    ${DNS_IP:-not found}"
    warn "SSL cannot be issued automatically yet."
    warn "Point $DOMAIN to this server and run:"
    warn "certbot --nginx -d $DOMAIN"
    return 0
  fi

  certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "$LE_EMAIL" \
    --redirect \
    -d "$DOMAIN"

  systemctl reload nginx
  ok "Let's Encrypt SSL configured."
}

finalize() {
  cd "$APP_DIR"
  chown -R www-data:www-data "$APP_DIR"
  chmod -R 755 storage bootstrap/cache
  sudo -u www-data php artisan optimize:clear
  systemctl restart php8.3-fpm
  systemctl restart redis-server
  systemctl restart paymenter
  nginx -t
  systemctl reload nginx

  cat > "$INFO_FILE" <<EOF
Paymenter installation
Domain: https://${DOMAIN}
Application directory: ${APP_DIR}
Admin username: ${ADMIN_USER}
Admin email: ${ADMIN_EMAIL}

Database:
Database: paymenter
Username: paymenter
Password: ${DB_PASS}

APP_KEY is stored in:
${APP_DIR}/.env

IMPORTANT:
Keep this file private. Do not upload it to GitHub.
EOF
  chmod 600 "$INFO_FILE"

  echo
  ok "Paymenter installation completed."
  echo "URL: https://${DOMAIN}"
  echo "Installer log: $LOG_FILE"
  echo "Private install info: $INFO_FILE"
  echo
  systemctl --no-pager --full status paymenter | sed -n '1,12p'
  echo
  php -m | grep -qi '^imap$' && ok "PHP IMAP is enabled." || warn "PHP IMAP check failed."
}

install() {
  require_ubuntu
  [[ ! -e "$APP_DIR" ]] || die "$APP_DIR already exists. Use the uninstall option first if this is an old test install."

  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  prompt_config
  install_packages
  install_paymenter
  setup_database
  run_interactive_init
  setup_cron_and_queue
  setup_nginx_http
  setup_ssl
  finalize
}

menu
