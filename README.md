# SKN Paymenter Installer — Fixed

Production-oriented Paymenter installer for Ubuntu 24.04.

## What was fixed

- Fixed the installer crash caused by the undefined `info` function.
- Fixed `app:init`: current Paymenter expects the company name and URL as positional arguments, so the installer now calls `php artisan app:init "COMPANY" "https://DOMAIN"`.
- Fixed admin creation input order to match the current Paymenter prompts: first name, last name, email, password, role.
- Added **resume mode** for a partial installation. If `/var/www/paymenter/.env` already exists, the installer can continue without replacing the existing database password.
- Keeps the existing Paymenter database when recovering from the failed run.
- Retains Nginx, Redis queue worker, cron scheduler, and optional Let's Encrypt setup.

## Important for your current failed install

Your previous run already completed the database migrations/seeding. When you run this fixed installer, choose **Install Paymenter**, then answer **Y** when it asks whether to resume the existing installation.

The installer reads the existing database password from `/var/www/paymenter/.env` so it does not break the existing database connection.

## Requirements

- Ubuntu 24.04
- Root access
- DNS A record for the billing domain
- TCP 22, 80 and 443 allowed by the VPS/AWS firewall

## Run

```bash
./install.sh
```

Official Paymenter documentation confirms Ubuntu 24.04 support and the current `app:init` / `app:user:create` workflow.


## Simple installation
After extracting the ZIP, no `chmod` or other setup command is required. Run:

```bash
./install.sh
```

If root privileges are needed, the installer automatically re-launches itself with `sudo`.
