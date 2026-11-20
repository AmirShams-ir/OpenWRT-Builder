# Smart-Net Bootstrap modules

`scripts/bootstrap.sh` is the orchestrator.

| Module | Responsibility |
| --- | --- |
| 00-system | APK metadata, base utilities, sysntpd, platform report |
| 01-memory | ZRAM package/device detection and swappiness |
| 02-kernel | BBR feature detection and conservative TCP settings |
| 03-security | OpenWrt firewall/logd baseline; preserves existing rules |
| 04-network | Diagnostics only; never changes WAN/LAN/Wi-Fi/DHCP/DNS |
| 05-wireguard | Optional WireGuard package compatibility |
| 06-proxy-stack | Optional packages from configured trusted feeds only |
| 07-docker | Conservative RAM/architecture gate |
| 08-webhosting | Minimal nginx package probe; service not started |

## Guarantees

- POSIX `/bin/sh` / BusyBox `ash`; no Bash, apt, systemd, UFW or journald.
- Does not partition, format, resize or mount disks. Installer99 owns storage.
- Does not rewrite network, wireless, DHCP, DNS or firewall rules.
- Does not add third-party APK feeds or fetch unsigned proxy binaries.
- Missing optional packages are reported; later modules still run.
- Report: `/root/smartnet-bootstrap-report.txt`; log: `/var/log/smartnet-bootstrap.log`.

Run as root:

```sh
sh /path/to/OpenWRT-Builder/scripts/bootstrap.sh
```

Passwall2, AmneziaWG, proxy cores, Docker, PHP-FPM and database hosting require
exact release/architecture/package/kernel-ABI verification before becoming
mandatory. AmneziaWG is deliberately not guessed or installed from an unknown feed.
