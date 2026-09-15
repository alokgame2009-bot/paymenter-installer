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

[[ -r /dev/tty ]] || { echo "This installer must be run from an interactive terminal."; exit 1; }

uninstall() {
  echo
  warn "This removes the Paymenter installation, its Nginx site, service and cron."
  warn "Shared packages such as PHP/MariaDB/Redis/Nginx are NOT removed."
  read -r -p "Type UNINSTALL to continue: " confirm < /dev/tty
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

  read -r -p "Also drop the Paymenter MariaDB database/user? [y/N]: " dropdb < /dev/tty
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
  clear 2>/dev/null || true
  echo
  printf '\033[1;36m╔══════════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[1;36m║              SKN PAYMENTER INSTALLER                       ║\033[0m\n'
  printf '\033[1;36m║                 INSTALLATION SETUP                         ║\033[0m\n'
  printf '\033[1;36m╚══════════════════════════════════════════════════════════════╝\033[0m\n'
  echo

  while true; do
    read -r -p "Domain [e.g. https://billing.example.com]: " DOMAIN < /dev/tty
    DOMAIN="${DOMAIN#http://}"; DOMAIN="${DOMAIN#https://}"; DOMAIN="${DOMAIN%%/*}"
    if [[ -n "$DOMAIN" && "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then break; fi
    warn "Invalid domain. Please enter a valid domain and try again."
  done
  while true; do
    read -r -p "Company Name [e.g. SkylerNodes]: " COMPANY < /dev/tty
    [[ -n "${COMPANY//[[:space:]]/}" ]] && break
    warn "Company name cannot be empty. Please try again."
  done
  while true; do
    read -r -p "First Name: " ADMIN_FIRST_NAME < /dev/tty
    [[ "$ADMIN_FIRST_NAME" =~ ^[[:alpha:]][[:alpha:][:space:]-]*$ ]] && break
    warn "Invalid first name. Please try again."
  done
  while true; do
    read -r -p "Last Name: " ADMIN_LAST_NAME < /dev/tty
    [[ "$ADMIN_LAST_NAME" =~ ^[[:alpha:]][[:alpha:][:space:]-]*$ ]] && break
    warn "Invalid last name. Please try again."
  done
  while true; do
    read -r -p "Email Address [e.g. admin@example.com]: " ADMIN_EMAIL < /dev/tty
    [[ "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && break
    warn "Invalid email address. Please try again."
  done
  while true; do
    read -r -s -p "Account Password [e.g. StrongPass123!]: " ADMIN_PASS < /dev/tty; echo
    if [[ ${#ADMIN_PASS} -ge 8 ]]; then break; fi
    warn "Password must be at least 8 characters. Please try again."
    ADMIN_PASS=""
  done
  while true; do
    read -r -p "Account Type (admin/user) [e.g. admin]: " ACCOUNT_TYPE < /dev/tty
    ACCOUNT_TYPE="${ACCOUNT_TYPE,,}"; [[ -z "$ACCOUNT_TYPE" ]] && ACCOUNT_TYPE="admin"
    [[ "$ACCOUNT_TYPE" == "admin" || "$ACCOUNT_TYPE" == "user" ]] && break
    warn "Account type must be admin or user. Please try again."
  done
  while true; do
    read -r -p "Let's Encrypt Email [e.g. admin@example.com]: " LE_EMAIL < /dev/tty
    [[ "$LE_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && break
    warn "Invalid Let's Encrypt email. Please try again."
  done

  ADMIN_NAME="${ADMIN_FIRST_NAME} ${ADMIN_LAST_NAME}"
  ADMIN_USER="${ADMIN_EMAIL%%@*}"
  echo
  printf '\033[1;36m╔══════════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[1;36m║                 INSTALLATION DETAILS                       ║\033[0m\n'
  printf '\033[1;36m╠══════════════════════════════════════════════════════════════╣\033[0m\n'
  printf '║ %-18s : %-38s ║\n' "Domain" "https://${DOMAIN}"
  printf '║ %-18s : %-38s ║\n' "Company" "$COMPANY"
  printf '║ %-18s : %-38s ║\n' "First name" "$ADMIN_FIRST_NAME"
  printf '║ %-18s : %-38s ║\n' "Last name" "$ADMIN_LAST_NAME"
  printf '║ %-18s : %-38s ║\n' "Email address" "$ADMIN_EMAIL"
  printf '║ %-18s : %-38s ║\n' "Login username" "$ADMIN_USER"
  printf '║ %-18s : %-38s ║\n' "Account type" "$ACCOUNT_TYPE"
  printf '║ %-18s : %-38s ║\n' "Let's Encrypt" "$LE_EMAIL"
  printf '║ %-18s : %-38s ║\n' "Password" "********"
  printf '\033[1;36m╚══════════════════════════════════════════════════════════════╝\033[0m\n'
  echo
  DB_PASS="$(openssl rand -hex 24)"
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

  log "Initializing Paymenter with the confirmed details..."

  # Current Paymenter defines app:init as: app:init {name} {url}.
  # Passing positional arguments avoids Laravel Prompts/terminal-menu issues.
  sudo -u www-data php artisan app:init "$COMPANY" "https://${DOMAIN}"

  log "Creating the Paymenter account..."
  if [[ "$ACCOUNT_TYPE" == "admin" ]]; then
    USER_ROLE="admin"
  else
    USER_ROLE="user"
  fi

  # Create/update the account directly through Laravel.
  # Paymenter's users table does NOT have a "name" column, so we only
  # write columns that actually exist in the installed schema.
  mkdir -p /tmp/paymenter-psysh
  chown www-data:www-data /tmp/paymenter-psysh
  chmod 700 /tmp/paymenter-psysh

  if ! sudo -u www-data env HOME=/tmp XDG_CONFIG_HOME=/tmp/paymenter-psysh \
    SKN_ADMIN_FIRST_NAME="$ADMIN_FIRST_NAME" \
    SKN_ADMIN_LAST_NAME="$ADMIN_LAST_NAME" \
    SKN_ADMIN_EMAIL="$ADMIN_EMAIL" \
    SKN_ADMIN_PASS="$ADMIN_PASS" \
    SKN_USER_ROLE="$USER_ROLE" \
    php artisan tinker --execute='$first=trim(getenv("SKN_ADMIN_FIRST_NAME")); $last=trim(getenv("SKN_ADMIN_LAST_NAME")); $email=strtolower(trim(getenv("SKN_ADMIN_EMAIL"))); $pass=getenv("SKN_ADMIN_PASS"); $roleName=strtolower(trim(getenv("SKN_USER_ROLE"))); $cols=\Illuminate\Support\Facades\Schema::getColumnListing("users"); $data=[]; if(in_array("first_name",$cols,true)){$data["first_name"]=$first;} if(in_array("last_name",$cols,true)){$data["last_name"]=$last;} if(in_array("email",$cols,true)){$data["email"]=$email;} if(in_array("password",$cols,true)){$data["password"]=\Illuminate\Support\Facades\Hash::make($pass);} if(in_array("role_id",$cols,true)){if(!\Illuminate\Support\Facades\Schema::hasTable("roles")){throw new \RuntimeException("Paymenter roles table not found.");} $roleId=\Illuminate\Support\Facades\DB::table("roles")->whereRaw("LOWER(name)=?",[$roleName])->value("id"); if(!$roleId){throw new \RuntimeException("Paymenter role not found: ".$roleName);} $data["role_id"]=$roleId;} elseif(in_array("name",$cols,true)){$data["name"]=trim($first." ".$last);} $now=now(); if(in_array("updated_at",$cols,true)){$data["updated_at"]=$now;} $existing=\Illuminate\Support\Facades\DB::table("users")->where("email",$email)->first(); if($existing){\Illuminate\Support\Facades\DB::table("users")->where("email",$email)->update($data);} else {if(in_array("created_at",$cols,true)){$data["created_at"]=$now;} \Illuminate\Support\Facades\DB::table("users")->insert($data);} echo "SKN_ADMIN_CREATED\n";'
  then
    die "Paymenter account creation failed. Check the error above."
  fi

  ok "Paymenter $USER_ROLE account created/updated successfully."
  unset SKN_ADMIN_FIRST_NAME SKN_ADMIN_LAST_NAME SKN_ADMIN_EMAIL SKN_ADMIN_PASS SKN_USER_ROLE

  sudo -u www-data php artisan app:settings:change app_url "https://${DOMAIN}" || true
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

loading() {
  local message="$1" pid="$2" i=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[1;36m%s\033[0m %s...' "${frames[$i]}" "$message"
    i=$(( (i + 1) % ${#frames[@]} )); sleep 0.08
  done
  printf '\r\033[2K'
}


create_user_admin() {
  clear 2>/dev/null || true
  echo
  printf '\033[1;36m╔══════════════════════════════════════════════════════════════╗\033[0m\n'
  printf '\033[1;36m║              CREATE PAYMENTER ACCOUNT                     ║\033[0m\n'
  printf '\033[1;36m╚══════════════════════════════════════════════════════════════╝\033[0m\n'
  echo

  [[ -d "$APP_DIR" && -f "$APP_DIR/artisan" && -f "$APP_DIR/.env" ]] || {
    warn "Paymenter is not installed at $APP_DIR. Install Paymenter first using option [1]."
    return 1
  }

  local NEW_FIRST NEW_LAST NEW_EMAIL NEW_PASS NEW_TYPE ROLE TINKER_CODE
  while true; do
    read -r -p "First Name: " NEW_FIRST < /dev/tty
    [[ "$NEW_FIRST" =~ ^[[:alpha:]][[:alpha:][:space:]-]*$ ]] && break
    warn "Invalid first name. Please try again."
  done
  while true; do
    read -r -p "Last Name: " NEW_LAST < /dev/tty
    [[ "$NEW_LAST" =~ ^[[:alpha:]][[:alpha:][:space:]-]*$ ]] && break
    warn "Invalid last name. Please try again."
  done
  while true; do
    read -r -p "Email Address [e.g. admin@example.com]: " NEW_EMAIL < /dev/tty
    [[ "$NEW_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && break
    warn "Invalid email address. Please try again."
  done
  while true; do
    read -r -s -p "Account Password: " NEW_PASS < /dev/tty; echo
    if [[ ${#NEW_PASS} -ge 8 ]]; then break; fi
    warn "Password must be at least 8 characters. Please try again."
  done
  while true; do
    read -r -p "Account Type (admin/user) [e.g. admin]: " NEW_TYPE < /dev/tty
    NEW_TYPE="${NEW_TYPE,,}"
    [[ "$NEW_TYPE" == "admin" || "$NEW_TYPE" == "user" ]] && break
    warn "Account type must be admin or user. Please enter admin or user."
  done

  [[ "$NEW_TYPE" == "admin" ]] && ROLE="admin" || ROLE="user"

  TINKER_CODE='$first=trim(getenv("SKN_NEW_FIRST")); $last=trim(getenv("SKN_NEW_LAST")); $email=strtolower(trim(getenv("SKN_NEW_EMAIL"))); $pass=getenv("SKN_NEW_PASS"); $roleName=strtolower(trim(getenv("SKN_NEW_ROLE"))); $cols=\Illuminate\Support\Facades\Schema::getColumnListing("users"); $data=[]; if(in_array("first_name",$cols,true)){$data["first_name"]=$first;} if(in_array("last_name",$cols,true)){$data["last_name"]=$last;} if(in_array("email",$cols,true)){$data["email"]=$email;} if(in_array("password",$cols,true)){$data["password"]=\Illuminate\Support\Facades\Hash::make($pass);} if(in_array("role_id",$cols,true)){if(!\Illuminate\Support\Facades\Schema::hasTable("roles")){throw new \RuntimeException("Paymenter roles table not found.");} $roleId=\Illuminate\Support\Facades\DB::table("roles")->whereRaw("LOWER(name)=?",[$roleName])->value("id"); if(!$roleId){throw new \RuntimeException("Paymenter role not found: ".$roleName);} $data["role_id"]=$roleId;} elseif(in_array("name",$cols,true)){$data["name"]=trim($first." ".$last);} $now=now(); if(in_array("updated_at",$cols,true)){$data["updated_at"]=$now;} $existing=\Illuminate\Support\Facades\DB::table("users")->where("email",$email)->first(); if($existing){\Illuminate\Support\Facades\DB::table("users")->where("email",$email)->update($data);} else {if(in_array("created_at",$cols,true)){$data["created_at"]=$now;} \Illuminate\Support\Facades\DB::table("users")->insert($data);} echo "SKN_ACCOUNT_CREATED\\n";'

  echo
  if ! run_step "Creating Paymenter account" env \
    SKN_NEW_FIRST="$NEW_FIRST" \
    SKN_NEW_LAST="$NEW_LAST" \
    SKN_NEW_EMAIL="$NEW_EMAIL" \
    SKN_NEW_PASS="$NEW_PASS" \
    SKN_NEW_ROLE="$ROLE" \
    SKN_TINKER_CODE="$TINKER_CODE" \
    bash -c 'cd "$1" && mkdir -p /tmp/paymenter-psysh && chown www-data:www-data /tmp/paymenter-psysh && chmod 700 /tmp/paymenter-psysh && sudo -u www-data env HOME=/tmp XDG_CONFIG_HOME=/tmp/paymenter-psysh SKN_NEW_FIRST="$SKN_NEW_FIRST" SKN_NEW_LAST="$SKN_NEW_LAST" SKN_NEW_EMAIL="$SKN_NEW_EMAIL" SKN_NEW_PASS="$SKN_NEW_PASS" SKN_NEW_ROLE="$SKN_NEW_ROLE" php artisan tinker --execute="$SKN_TINKER_CODE"' _ "$APP_DIR"; then
    warn "Account creation failed. Check $LOG_FILE for details."
    return 1
  fi

  unset NEW_FIRST NEW_LAST NEW_EMAIL NEW_PASS NEW_TYPE ROLE TINKER_CODE
  ok "Paymenter account created/updated successfully."
  return 0
}

update_paymenter() {
  if [[ ! -d "$APP_DIR" || ! -f "$APP_DIR/artisan" ]]; then
    warn "Paymenter is not installed at $APP_DIR. Install Paymenter first using option [1]."
    return 1
  fi

  echo
  warn "Paymenter update will put the billing panel into maintenance mode temporarily."
  printf '%b' "${C4}Continue with the latest Paymenter update? [y/N]: ${NC}"
  read -r UPDATE_CONFIRM < /dev/tty
  [[ "${UPDATE_CONFIRM,,}" == "y" || "${UPDATE_CONFIRM,,}" == "yes" ]] || {
    warn "Update cancelled."
    return 0
  }

  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  # Paymenter's official updater handles the release download and upgrade.
  if ! run_step "Updating Paymenter to the latest release" bash -c 'cd "$1" && php artisan app:upgrade' _ "$APP_DIR"; then
    warn "Paymenter update failed. Check $LOG_FILE for details."
    return 1
  fi

  if ! run_step "Refreshing Paymenter cache and permissions" bash -c 'cd "$1" && chmod -R 755 storage/* bootstrap/cache/ && php artisan optimize:clear && chown -R www-data:www-data "$1"' _ "$APP_DIR"; then
    warn "Post-update configuration failed. Check $LOG_FILE for details."
    return 1
  fi

  systemctl restart paymenter.service 2>/dev/null || true
  ok "Paymenter has been updated successfully."
  return 0
}

show_menu() {
  clear 2>/dev/null || true

  # Random RGB/TrueColor palette generated on every menu launch.
  rgb() {
    printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"
  }
  reset_color() { printf '\033[0m'; }
  random_rgb() {
    local r g b
    r=$((RANDOM % 256)); g=$((RANDOM % 256)); b=$((RANDOM % 256))
    rgb "$r" "$g" "$b"
  }

  local C1 C2 C3 C4 C5 C6 C7
  C1="$(random_rgb)"; C2="$(random_rgb)"; C3="$(random_rgb)"
  C4="$(random_rgb)"; C5="$(random_rgb)"; C6="$(random_rgb)"; C7="$(random_rgb)"

  echo
  printf '%b\n' "${C1}        ███████╗██╗  ██╗███╗   ██╗${NC}"
  printf '%b\n' "${C2}        ██╔════╝██║  ██║████╗  ██║${NC}"
  printf '%b\n' "${C3}        ███████╗█████╔╝██╔██╗ ██║${NC}"
  printf '%b\n' "${C4}        ╚════██║██╔═██╗ ██║╚██╗██║${NC}"
  printf '%b\n' "${C5}        ███████║██║  ██╗██║ ╚████╔╝${NC}"
  printf '%b\n' "${C6}        ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝${NC}"
  echo
  printf '%b\n' "${C7}                 S K N${NC}"
  printf '%b\n' "${C1}          PAYMENTER INSTALLER${NC}"
  printf '%b\n' "${C2}       Secure • Fast • Automated${NC}"
  echo
  printf '%b\n' "${C3}                  Made by Zyren${NC}"
  echo
  printf '%b\n' "${C4}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  printf '%b\n' "${C5}   [1]  Install Paymenter${NC}"
  printf '%b\n' "${C6}        Deploy a complete Paymenter server${NC}"
  echo
  printf '%b\n' "${C1}   [2]  Uninstall Paymenter${NC}"
  printf '%b\n' "${C7}        Safely remove the Paymenter installation${NC}"
  echo
  printf '%b\n' "${C2}   [3]  Create User/Admin${NC}"
  printf '%b\n' "${C2}        Create or update a Paymenter account${NC}"
  echo
  printf '%b\n' "${C6}   [4]  Update Paymenter${NC}"
  printf '%b\n' "${C6}        Upgrade the billing panel to the latest release${NC}"
  echo
  printf '%b\n' "${C1}   [5]  Exit${NC}"
  echo
  printf '%b\n' "${C3}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  printf '%b' "${C4}   Select an option [1-5]: ${NC}"
  read -r MENU_CHOICE < /dev/tty

  case "$MENU_CHOICE" in
    1)
      if install; then
        echo; printf '%b\n' "${C3}Installation process finished. Returning to main menu...${NC}"
      else
        echo; printf '%b\n' "${C1}Installation stopped safely. Returning to main menu...${NC}"
      fi
      sleep 1
      ;;
    2)
      if uninstall; then
        echo; printf '%b\n' "${C3}Uninstall process finished. Returning to main menu...${NC}"
      else
        echo; printf '%b\n' "${C1}Uninstall stopped safely. Returning to main menu...${NC}"
      fi
      sleep 1
      ;;
    3)
      if create_user_admin; then
        echo; printf '%b\n' "${C3}Account process finished. Returning to main menu...${NC}"
      else
        echo; printf '%b\n' "${C1}Account process stopped safely. Returning to main menu...${NC}"
      fi
      sleep 1
      ;;
    4)
      if update_paymenter; then
        echo; printf '%b\n' "${C3}Update process finished. Returning to main menu...${NC}"
      else
        echo; printf '%b\n' "${C1}Update stopped safely. Returning to main menu...${NC}"
      fi
      sleep 1
      ;;
    5)
      printf '%b\n' "${C3}Goodbye. Made by Zyren.${NC}"; exit 0
      ;;
    *)
      printf '%b\n' "${C1}Invalid option. Please select 1, 2, 3, 4, or 5.${NC}"; sleep 1
      ;;
  esac
}

run_step() {
  local label="$1"; shift
  "$@" &
  local pid=$!
  loading "$label" "$pid"
  if ! wait "$pid"; then
    warn "$label failed. Returning to the main menu."
    return 1
  fi
  return 0
}

install() {
  require_ubuntu

  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"

  if [[ -e "$APP_DIR" ]]; then
    echo
    warn "A Paymenter directory already exists at $APP_DIR."
    warn "This looks like a previous installation that stopped part-way through."
    RESUME="Y"

    [[ -f "$APP_DIR/.env" ]] || die "$APP_DIR exists but .env is missing. Remove the incomplete directory and run again."

    # Read the existing database password before prompt_config generates a new one.
    DB_PASS="$(grep -E '^DB_PASSWORD=' "$APP_DIR/.env" | head -n1 | cut -d= -f2-)"
    [[ -n "$DB_PASS" ]] || die "Could not read the existing Paymenter DB password from .env."

    prompt_config
    # Keep the existing DB credential; do not replace it during recovery.
    DB_PASS="$(grep -E '^DB_PASSWORD=' "$APP_DIR/.env" | head -n1 | cut -d= -f2-)"

    log "Resuming existing Paymenter installation..."
    chown -R www-data:www-data "$APP_DIR"
    chmod -R 755 "$APP_DIR/storage" "$APP_DIR/bootstrap/cache"

    # Database/migrations already completed in the failed run. Re-apply the
    # credentials and safely run migrations/seeding again (Laravel is idempotent).
    if ! run_step "Configuring Paymenter database" setup_database; then return 1; fi
  else
    prompt_config
    if ! run_step "Installing prerequisites" install_packages; then return 1; fi
    if ! run_step "Downloading Paymenter" install_paymenter; then return 1; fi
    if ! run_step "Configuring Paymenter database" setup_database; then return 1; fi
  fi

  if ! run_step "Initializing Paymenter" run_interactive_init; then return 1; fi
  if ! run_step "Configuring queue and scheduler" setup_cron_and_queue; then return 1; fi
  if ! run_step "Configuring Nginx" setup_nginx_http; then return 1; fi
  if ! run_step "Configuring SSL" setup_ssl; then return 1; fi
  if ! run_step "Finalizing Paymenter" finalize; then return 1; fi
}

while true; do
  show_menu
done
