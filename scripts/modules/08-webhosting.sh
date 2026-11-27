#!/bin/sh
# Smart-Net Module 08: generic WebApp Hosting foundation (OpenWrt APK).
# Static Vue/Vite and React builds are served by Nginx; backend runtimes are
# app/container-specific and must be verified for the device ABI.
set -eu

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
LOG="${SMARTNET_LOG_FILE:-/var/log/smartnet-bootstrap.log}"
BASE="/home/smartnet/webhosting"
APPS="$BASE/apps"
CONF_DIR="/etc/nginx/conf.d"
VHOST="$CONF_DIR/smartnet-webhosting.conf"
MAIN="/etc/nginx/nginx.conf"
CLI="/usr/sbin/smartnet-webhosting"
SERVICE="/etc/init.d/smartnet-webhosting"
REPO_FILES="${SMARTNET_ROOT_DIR:-/root/OpenWRT-Builder}/files"

log() { printf '%s\n' "[08-webhosting] $*"; printf '%s\n' "[08-webhosting] $*" >> "$LOG" 2>/dev/null || true; }
report() { printf '%s\n' "$*" >> "$REPORT" 2>/dev/null || true; }
fail() { log "ERROR: $*"; report "08-webhosting: FAILED - $*"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root"
have apk || fail "APK package manager not found"
[ -r /etc/openwrt_release ] || fail "not an OpenWrt system"
. /etc/openwrt_release

ARCH="$(apk --print-arch 2>/dev/null || echo unknown)"
CPU="$(uname -m 2>/dev/null || echo unknown)"
RAM_KB="$(awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
log "Release=${DISTRIB_RELEASE:-unknown}; package-arch=$ARCH; CPU=$CPU; RAM=$((RAM_KB / 1024))MiB"

# Installer99 must provide the persistent ext4 data mount. Never fill rootfs.
MOUNT="$(awk '$2=="/home/smartnet" {print $3; exit}' /proc/mounts)"
[ -n "$MOUNT" ] || fail "/home/smartnet is not mounted; refusing to install hosting data on rootfs"
[ "$MOUNT" = "ext4" ] || fail "/home/smartnet must be ext4 (found $MOUNT)"
FREE_KB="$(df -Pk /home/smartnet | awk 'NR==2 {print $4}')"
[ "$((FREE_KB / 1024))" -ge 512 ] || fail "at least 512MiB free required on /home/smartnet"

apk update || fail "apk update failed"
apk search -x nginx | grep -q '^nginx-' || fail "native nginx package unavailable for $ARCH"
apk add nginx || fail "could not install nginx from configured native repositories"
have nginx || fail "nginx executable missing after package installation"

mkdir -p "$APPS" "$BASE/logs" "$BASE/tmp" "$CONF_DIR" /etc/nginx/smartnet-apps
chmod 0750 "$BASE" "$APPS" "$BASE/logs" "$BASE/tmp"
[ "$(df -P "$BASE" | awk 'NR==2 {print $NF}')" = "/home/smartnet" ] || fail "hosting data is not on persistent /home/smartnet"

# Create an app-neutral landing site. AmirNote is just another app directory.
if [ ! -d "$APPS/default" ]; then
    mkdir -p "$APPS/default/public" "$APPS/default/data" "$APPS/default/db" "$APPS/default/logs" "$APPS/default/config"
    cat > "$APPS/default/public/index.html" <<'HTML'
<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Smart-Net WebApp Hosting</title>
<h1>Smart-Net WebApp Hosting</h1>
<p>Hosting is installed. Publish a static site under an app's public directory.</p>
</html>
HTML
    printf '%s\n' '{"name":"default","type":"static","enabled":true}' > "$APPS/default/config/app.json"
fi

# Build a minimal complete nginx.conf when the package does not provide one.
# If one exists, preserve it and add our include exactly once.
if [ ! -f "$MAIN" ]; then
    cat > "$MAIN" <<'NGINX'
worker_processes 1;
pid /var/run/nginx.pid;
events { worker_connections 256; }
http {
    types {
        text/html html htm;
        text/css css;
        application/javascript js mjs;
        application/json json;
        image/svg+xml svg;
        image/png png;
        image/jpeg jpg jpeg;
        image/gif gif;
        image/webp webp;
        font/woff woff;
        font/woff2 woff2;
    }
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 30;
    client_body_temp_path /home/smartnet/webhosting/tmp/client_body;
    proxy_temp_path /home/smartnet/webhosting/tmp/proxy;
    include /etc/nginx/conf.d/*.conf;
}
NGINX
else
    if ! grep -Fq 'include /etc/nginx/conf.d/*.conf;' "$MAIN"; then
        cp -p "$MAIN" "$MAIN.smartnet-backup"
        if grep -q '^[[:space:]]*http[[:space:]]*{' "$MAIN"; then
            sed -i '/^[[:space:]]*http[[:space:]]*{/a\    include /etc/nginx/conf.d/*.conf;' "$MAIN"
        else
            fail "existing nginx.conf has no recognizable http block; backed up and left unchanged"
        fi
    fi
fi

# Replace only our managed vhost. The listener stays on 8080; LuCI/uHTTPd
# retains its existing ports. Rewrite app URLs to each app's public directory.
cat > "$VHOST" <<'NGINX'
server {
    listen 8080;
    listen [::]:8080;
    server_name _;
    root /home/smartnet/webhosting;
    index index.html;
    access_log /home/smartnet/webhosting/logs/access.log;
    error_log /home/smartnet/webhosting/logs/error.log;
    client_max_body_size 8m;

    # Reject private app paths before the server-level rewrites.
    if ($uri ~* ^/apps/[a-z0-9][a-z0-9_-]*/(data|db|logs|config)/) { return 404; }
    location ~ /\\. { deny all; }

    rewrite ^/$ /apps/default/public/index.html last;
    rewrite ^/apps/([a-z0-9][a-z0-9_-]*)/?$ /apps/$1/public/index.html last;
    include /etc/nginx/smartnet-apps/*.conf;
    rewrite ^/apps/([a-z0-9][a-z0-9_-]*)/(?!public/|api/)(.*)$ /apps/$1/public/$2 last;

    location ~ ^/apps/([a-z0-9][a-z0-9_-]*)/public/ {
        try_files $uri $uri/ /apps/$1/public/index.html;
    }
    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX

# Install repository-owned LuCI/service assets before validation.
for rel in \
    usr/share/luci/menu.d/luci-app-smartnet-webhosting.json \
    usr/share/rpcd/acl.d/luci-app-smartnet-webhosting.json \
    www/luci-static/resources/view/smartnet/webhosting.js \
    etc/init.d/smartnet-webhosting \
    usr/sbin/smartnet-webhosting; do
    dst="/$rel"
    if [ -f "$REPO_FILES/$rel" ]; then
        mkdir -p "/$(dirname "$rel")"
        case "$rel" in
            etc/init.d/*|usr/sbin/*) install -m 0755 "$REPO_FILES/$rel" "$dst" ;;
            *) install -m 0644 "$REPO_FILES/$rel" "$dst" ;;
        esac
    elif [ ! -f "$dst" ]; then
        fail "asset unavailable in repo and installed system: files/$rel"
    fi
done

[ -x "$CLI" ] || fail "hosting CLI missing"
[ -f /usr/share/luci/menu.d/luci-app-smartnet-webhosting.json ] || fail "LuCI menu missing"
[ -f /www/luci-static/resources/view/smartnet/webhosting.js ] || fail "LuCI view missing"
[ -f /usr/share/rpcd/acl.d/luci-app-smartnet-webhosting.json ] || fail "LuCI ACL missing"
[ -x "$SERVICE" ] || chmod 0755 "$SERVICE"

nginx -t || fail "nginx configuration test failed; nginx not started"
[ -x /etc/init.d/nginx ] || fail "nginx procd init script missing"
 /etc/init.d/nginx enable || fail "could not enable nginx"
if pidof nginx >/dev/null 2>&1; then
    /etc/init.d/nginx reload || fail "nginx reload failed"
else
    /etc/init.d/nginx start || fail "nginx start failed"
fi

[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
[ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd reload >/dev/null 2>&1 || true

report "08-webhosting: generic app hosting initialized at $APPS; Nginx listener tcp/8080"
report "08-webhosting: create/list apps with: smartnet-webhosting create <slug> | list"
report "08-webhosting: each app has public/data/db/logs/config; SQLite file is app-owned in db/"
if have sqlite3; then report "08-webhosting: sqlite3 CLI detected"; else report "08-webhosting: sqlite3 CLI absent; app/container may use its own SQLite library"; fi
if have node; then report "08-webhosting: Node runtime detected: $(node --version 2>/dev/null || echo unknown)"; else report "08-webhosting: no native Node runtime detected; static builds can still be hosted"; fi
log "Generic WebApp Hosting foundation installed; uHTTPd ports unchanged."
