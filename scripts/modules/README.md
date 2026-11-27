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
| 08-webhosting | Generic persistent web-app hosting, Nginx :8080, per-app storage layout, CLI and LuCI status page |

## Module 08 — Generic WebApp Hosting

Module 08 requires Installer99 to mount `/home/smartnet` as ext4 with at least 512 MiB free. It refuses to place app data on rootfs.

### Architecture

Persistent app root:

```
/home/smartnet/webhosting/apps/<slug>/
├── public/   # frontend production build (served by Nginx)
├── data/     # app-owned persistent files
├── db/       # app-owned SQLite file(s), e.g. app.sqlite
├── logs/     # app-specific logs
└── config/   # non-secret app metadata/config
```

AmirNote is not special-cased: it can be created as an app after its API/storage compatibility work is completed. Static Vue/Vite and React builds can be built on a PC or CI and copied to `public/`; the router does not need Node just to serve static assets.

Nginx listens on TCP/8080 so LuCI/uHTTPd ports 80/443 are preserved. App URLs are:

```
http://<Smart-Net-LAN-IP>:8080/apps/<slug>/
```

Module 08 creates a minimal `/etc/nginx/nginx.conf` only when missing. If an existing config lacks the managed include, it is backed up before a safe include insertion. Only the module's own vhost is replaced. `nginx -t` must pass before the service is started/reloaded.

### App CLI

```sh
smartnet-webhosting list
smartnet-webhosting create my-app
smartnet-webhosting info my-app
smartnet-webhosting container-run my-app my-local-image:tag 3000 13000
smartnet-webhosting container-status my-app
smartnet-webhosting container-stop my-app
smartnet-webhosting container-remove my-app
```

Creation is non-destructive; there is deliberately no delete command. Publish a Vite/React build by copying the contents of its build output (usually `dist/`) into the app's `public/` directory.

### Optional Docker backend

If Module 07 has installed a working Docker daemon, Module 08 provides a root-only CLI to run a locally available per-app container. The image is not pulled automatically: first obtain it, then verify it supports Linux `386/i386`. The command refuses other image architectures. This matters on the Clientron's 32-bit i686 userspace; do not assume amd64/arm64 images work.

`container-run` binds the container port only to localhost, mounts the app's persistent `data/` and `db/` directories, and adds an Nginx route at `/apps/<slug>/api/`. The container is expected to listen on the supplied port and use `/app/data` and `/app/db` for persistent paths. `container-remove` removes the container and proxy route but preserves app data and the SQLite directory.

### SQLite and backend containers

SQLite is embedded, not a database server. Each app may create and manage its own DB at:

```
/home/smartnet/webhosting/apps/<slug>/db/app.sqlite
```

The database is created by the app's SQLite runtime, not by the static hosting module. A backend/container must be verified for the device's actual 32-bit architecture and resource limits. Do not assume a standard Node image supports i686. Use persistent mounts for app `data/` and `db/`; never place secrets in public frontend assets.

Current AmirNote uses Vercel Functions and Vercel Blob. Static deployment alone will not provide its API or Blob storage; adapt the API and storage layer or retain a securely configured server-side external storage integration. Never expose `BLOB_READ_WRITE_TOKEN` in `VITE_*` variables.

### LuCI

The read-only LuCI page shows the generic layout, deployment commands and architecture cautions. It does not pretend to be a full Docker control panel or create containers through browser-side shell commands. Container lifecycle and dynamic reverse-proxy integration require a separate verified backend/API module.

### Safety guarantees

- BusyBox `ash` / POSIX shell; no Bash, apt, systemd, UFW or journald.
- Does not partition, format, resize or mount disks.
- Does not change WAN/LAN/Wi-Fi/DHCP/DNS/firewall rules.
- Does not add third-party APK feeds or download foreign-ABI runtimes.
- Preserves uHTTPd ports and starts/reloads Nginx only after `nginx -t`.
- Report: `/root/smartnet-bootstrap-report.txt`; log: `/var/log/smartnet-bootstrap.log`.

Run as root:

```sh
sh /path/to/OpenWRT-Builder/scripts/bootstrap.sh
```
