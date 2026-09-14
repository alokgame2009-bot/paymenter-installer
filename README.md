# SKN — Paymenter One-Command Installer

**Made by Zyren**


**Made by Zyren**

**Made by Zyren**

Production-oriented installer for Paymenter on Ubuntu 24.04.

## What it installs

- PHP 8.3 + Paymenter dependencies
- PHP IMAP
- MariaDB 10.11
- Redis
- Nginx
- Composer
- Latest official Paymenter release
- Database and random database password
- `.env` and APP_KEY
- Database migrations/seeding
- `app:init`
- `app:user:create`
- Cron scheduler
- systemd queue worker
- Nginx
- Let's Encrypt SSL when DNS already points to the server
- Final health checks

## One command

After putting `install.sh` in your GitHub repository:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/paymenter-installer/main/install.sh)
```

Replace `YOUR_USERNAME/paymenter-installer` with your real GitHub repository.

## Requirements

- Ubuntu 24.04
- Root/sudo access
- Domain A record pointing to the VPS for automatic SSL
- AWS/security-group or VPS firewall must allow TCP 22, 80 and 443

## Important

The installer deliberately runs Paymenter's `app:init` and `app:user:create` interactively instead of guessing their prompts. This is safer across Paymenter updates. Paymenter files are prepared before database Artisan commands run, so a fresh install does not depend on a pre-existing `/var/www/paymenter` directory.

The installer never places your admin password or generated database password into the GitHub repository.

Install log:
`/var/log/paymenter-installer.log`

Private installation information:
`/root/paymenter-install-info.txt`

## Uninstall

Run the installer again and choose:

`2) Uninstall Paymenter`

It removes the Paymenter application, Nginx site, queue service and scheduler. It asks separately whether to remove the Paymenter database/user.

It does not remove shared PHP, MariaDB, Redis or Nginx packages.

## Official references

- https://paymenter.org/docs/installation/install
- https://paymenter.org/docs/installation/webserver
- https://paymenter.org/docs/guides/cli

### Partial-install cleanup
If a previous installation stopped halfway, the installer detects `/var/www/paymenter` and asks whether to remove that **application directory only** before continuing. It does not automatically delete shared MariaDB, Redis, Nginx, or PHP packages.

### One-time setup details
The installer asks for the domain, company name, admin details, and Let's Encrypt email **once**, shows a confirmation screen, and then reuses those values automatically for Paymenter's initialization and admin creation. It does not ask you to enter the same details again during `app:init` or `app:user:create`.
