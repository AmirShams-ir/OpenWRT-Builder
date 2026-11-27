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
| 08-webhosting | Persistent Nginx site root, isolated :8080 listener, procd app runner, and read-only LuCI status page |

## Web hosting module

Module 08 expects Installer99 to have mounted `/home/smartnet` as ext4. It refuses to write hosting content to rootfs when that mount is absent or has less than 512 MiB free.

It installs Nginx from the device's configured APK repositories and configures a dedicated virtual host on TCP/8080. LuCI/uHTTPd ports 80/443 are not changed. The managed site root is:

```
/home/smartnet/webhosting/sites/amirnote
```

The module installs these LuCI assets:

- `files/usr/share/luci/menu.d/luci-app-smartnet-webhosting.json`
- `files/usr/share/rpcd/acl.d/luci-app-smartnet-webhosting.json`
- `files/www/luci-static/resources/view/smartnet/webhosting.js`

The procd runner is installed as `/etc/init.d/smartnet-webhosting`, but remains inert until a compatible `/usr/bin/node` and `/home/smartnet/webhosting/app/server.js` exist.

### AmirNote compatibility

Current AmirNote uses Vue/Vite for its frontend, Vercel Functions for `api/`, and private Vercel Blob storage via `BLOB_READ_WRITE_TOKEN`. Module 08 does not pretend that a static Vite build is a complete deployment. A compatible API runtime and storage adapter must be provisioned separately before AmirNote data operations are enabled. Never put the Blob token in a `VITE_*` variable or static frontend file.

Node.js is probed only; it is not downloaded from unofficial feeds or foreign architectures. This is intentional for x86/generic i386_pentium4.

## Guarantees

- POSIX `/bin/sh` / BusyBox `ash`; no Bash, apt, systemd, UFW or journald.
- Does not partition, format, resize or mount disks. Installer99 owns storage.
- Does not rewrite network, wireless, DHCP, DNS or firewall rules.
- Does not add third-party APK feeds or fetch unsigned proxy binaries.
- Missing optional runtimes are reported; later modules can continue.
- Report: `/root/smartnet-bootstrap-report.txt`; log: `/var/log/smartnet-bootstrap.log`.

Run as root:

```sh
sh /path/to/OpenWRT-Builder/scripts/bootstrap.sh
```

Passwall2, AmneziaWG, proxy cores, Docker, PHP-FPM and database hosting require exact release/architecture/package/kernel-ABI verification before becoming mandatory. AmneziaWG is deliberately not guessed or installed from an unknown feed.
