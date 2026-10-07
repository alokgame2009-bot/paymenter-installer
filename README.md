# NexyonCloud Paymenter Installer

Made by Hiro

## Supported OS

- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

## Features

- Install / Uninstall / Exit menu
- Create User/Admin accounts
- Update Paymenter
- Existing Paymenter installation resume support
- RGB terminal menu
- Animated loading indicator
- Nginx + SSL
- MariaDB + Redis
- PHP 8.3
- Automatic database setup
- Paymenter queue worker and scheduler

## Run

```bash
chmod +x install.sh
sudo bash install.sh
```

## One-liner

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alokgame2009-bot/paymenter-installer/main/install.sh)
```

Do not expose `/root/paymenter-install-info.txt` or the Paymenter `.env` file publicly.
