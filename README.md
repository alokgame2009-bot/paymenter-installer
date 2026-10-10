# NexyonCloud Paymenter Installer (patched)

This package contains the patched installer and documentation.

## Supported OS
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

## Run
```bash
chmod +x install.sh
sudo bash install.sh
```

## Log troubleshooting
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
- The installer has been syntax-checked with `bash -n`. It has not been run against your AWS VPS, so environment-specific failures may still need the log output to diagnose.
- Keep `/root/paymenter-install-info.txt` and `/var/www/paymenter/.env` private.
