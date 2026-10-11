# NexyonCloud Paymenter Installer

Paymenter installer with interactive install, uninstall, account management, and update options.

## Supported operating systems
- Debian 11
- Debian 12
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

The installer uses PHP 8.3 and configures the appropriate PHP package repository for Ubuntu or Debian.

## Run
```bash
chmod +x install.sh
sudo bash install.sh
```

## Troubleshooting
Installer log: `/var/log/paymenter-installer.log`

```bash
tail -n 150 /var/log/paymenter-installer.log
systemctl status paymenter --no-pager -l
journalctl -u paymenter -n 100 --no-pager
nginx -t
```

## Notes
- The installer preserves Nginx's default site and other sites.
- Uninstall removes the Paymenter cron file, service, and Paymenter Nginx site.
- Shared packages (PHP, MariaDB, Redis, Nginx) and SSL certificates are intentionally preserved.
- Debian/Ubuntu installation was syntax-checked, but not executed on a live VPS. Repository availability and Paymenter upstream changes can still affect installation.
- Keep `/root/paymenter-install-info.txt` and `/var/www/paymenter/.env` private.

**Made by Ziro**
