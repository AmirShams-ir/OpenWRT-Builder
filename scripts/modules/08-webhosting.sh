#!/bin/sh
# Smart-Net Module 08: WebApp Hosting foundation (OpenWrt 25.12+, APK).
# Installs only native packages available for the running OpenWrt architecture.
# Nginx is configured on :8080 to avoid collision with LuCI/uhttpd on :80/:443.
# Node.js is probed, never fetched from third-party or mismatched architecture feeds.
set -eu

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
LOG="${SMARTNET_LOG_FILE:-/var/log/smartnet-bootstrap.log}"
WEBROOT="/home/smartnet/webhosting"
SITES="$WEBROOT/sites"
CONFIG="$WEBROOT/config"
LOGDIR="$WEBROOT/logs"
NGINX_CONF="/etc/nginx/conf.d/smartnet-webhosting.conf"
NGINX_MAIN="/etc/nginx/nginx.conf"
LUCI_MENU="/usr/share/luci/menu.d/luci-app-smartnet-webhosting.json"
LUCI_VIEW="/www/luci-static/resources/view/smartnet/webhosting.js"
LUCI_ACL="/usr/share/rpcd/acl.d/luci-app-smartnet-webhosting.json"
SERVICE="/etc/init.d/smartnet-webhosting"

log() {
    printf '%s\n' "[08-webhosting] $*"
    printf '%s\n' "[08-webhosting] $*" >> "$LOG" 2>/dev/null || true
}
report() {
    printf '%s\n' "$*" >> "$REPORT" 2>/dev/null || true
}
fail() {
    log "ERROR: $*"
    report "08-webhosting: FAILED - $*"
    exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root"
have apk || fail "APK package manager not found"
have uci || fail "UCI not found"
[ -r /etc/openwrt_release ] || fail "not an OpenWrt system"
. /etc/openwrt_release

ARCH="$(apk --print-arch 2>/dev/null || echo unknown)"
CPU="$(uname -m 2>/dev/null || echo unknown)"
RAM_KB="$(awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
RAM_MB=$((RAM_KB / 1024))
log "Release=${DISTRIB_RELEASE:-unknown}; package-arch=$ARCH; CPU=$CPU; RAM=${RAM_MB}MiB"

# Require Installer99's persistent data mount. Never silently fill rootfs.
MOUNT="$(awk '$2=="/home/smartnet" {print $3; exit}' /proc/mounts)"
[ -n "$MOUNT" ] || fail "/home/smartnet is not mounted; refusing to install web data on rootfs"
[ "$MOUNT" = "ext4" ] || fail "/home/smartnet must be ext4 (found $MOUNT)"
FREE_KB="$(df -Pk /home/smartnet | awk 'NR==2 {print $4}')"
FREE_MB=$((FREE_KB / 1024))
[ "$FREE_MB" -ge 512 ] || fail "need at least 512MiB free on /home/smartnet; found ${FREE_MB}MiB"

# Ensure native Nginx comes from this device's configured OpenWrt APK repositories.
apk update || fail "apk update failed"
apk search -x nginx | grep -q '^nginx-' || fail "native nginx package unavailable for $ARCH"
if ! apk add nginx; then
    fail "could not install nginx for $ARCH"
fi
have nginx || fail "nginx executable missing after package installation"

# Detect executable ABI; do not trust nginx -v's build label alone.
NGINX_ABI="$(readelf -h "$(command -v nginx)" 2>/dev/null | awk -F: '/Class:|Machine:/ {gsub(/^[ \t]+/,"",$2); printf "%s ",$2}' || true)"
log "Nginx ELF: ${NGINX_ABI:-readelf unavailable}"

# Create persistent web-hosting layout.
mkdir -p "$SITES/amirnote" "$CONFIG" "$LOGDIR" "$WEBROOT/tmp"
chmod 0750 "$WEBROOT" "$SITES" "$SITES/amirnote" "$CONFIG" "$LOGDIR"
chown -R root:root "$WEBROOT"
[ "$(df -P "$WEBROOT" | awk 'NR==2 {print $NF}')" = "/home/smartnet" ] || fail "web root is not on persistent /home/smartnet filesystem"

# Preserve package-provided nginx.conf; add an isolated include in http context.
if [ ! -f "$NGINX_MAIN" ]; then
    fail "nginx.conf not found; package layout is not recognized"
fi
if ! grep -q 'include /etc/nginx/conf.d/\*.conf;' "$NGINX_MAIN"; then
    if grep -q '^http[[:space:]]*{' "$NGINX_MAIN"; then
        cp -p "$NGINX_MAIN" "$NGINX_MAIN.smartnet-backup"
        sed -i '/^http[[:space:]]*{/a\    include /etc/nginx/conf.d/*.conf;' "$NGINX_MAIN"
    else
        fail "cannot safely locate nginx http block; main config left unchanged"
    fi
fi

# Back up only our own managed vhost file.
if [ -f "$NGINX_CONF" ]; then
    cp -p "$NGINX_CONF" "$NGINX_CONF.smartnet-backup"
fi
cat > "$NGINX_CONF" <<'NGINX'
server {
    listen 8080;
    listen [::]:8080;
    server_name _;
    root /home/smartnet/webhosting/sites/amirnote;
    index index.html;

    access_log /home/smartnet/webhosting/logs/access.log;
    error_log  /home/smartnet/webhosting/logs/error.log;

    client_max_body_size 8m;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # Reserved API upstream. Enable only after a compatible AmirNote API
    # runtime and storage adapter have been deployed.
    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location ~ /\. {
        deny all;
    }
}
NGINX

nginx -t || fail "nginx configuration test failed; service not started"
if [ -x /etc/init.d/nginx ]; then
    /etc/init.d/nginx enable || fail "could not enable nginx"
    /etc/init.d/nginx start || fail "could not start nginx"
else
    fail "nginx init script is missing"
fi

# Provide an OpenWrt procd service wrapper for future API runtime, but keep it
# disabled until an actual compatible Node executable/app adapter exists.
cat > "$SERVICE" <<'INIT'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=95
STOP=10
start_service() {
    [ -x /usr/bin/node ] || return 0
    [ -f /home/smartnet/webhosting/app/server.js ] || return 0
    procd_open_instance
    procd_set_param command /usr/bin/node /home/smartnet/webhosting/app/server.js
    procd_set_param respawn 3600 5 5
    procd_set_param file /home/smartnet/webhosting/app/server.js
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
INIT
chmod 0755 "$SERVICE"

# Install managed LuCI assets from the repository when running on an
# already-installed router. ImageBuilder also ships these through files/.
REPO_FILES="${SMARTNET_ROOT_DIR:-/root/OpenWRT-Builder}/files"
if [ -d "$REPO_FILES" ]; then
    for rel in \
        usr/share/luci/menu.d/luci-app-smartnet-webhosting.json \
        usr/share/rpcd/acl.d/luci-app-smartnet-webhosting.json \
        www/luci-static/resources/view/smartnet/webhosting.js \
        etc/init.d/smartnet-webhosting; do
        [ -f "$REPO_FILES/$rel" ] || continue
        mkdir -p "/$(dirname "$rel")"
        install -m 0644 "$REPO_FILES/$rel" "/$rel"
    done
fi

# LuCI menu, view and ACL. No shell command RPC exposure; view is read-only
# status/links and never accepts arbitrary commands.
mkdir -p "$(dirname "$LUCI_MENU")" "$(dirname "$LUCI_VIEW")" "$(dirname "$LUCI_ACL")"
cat > "$LUCI_MENU" <<'MENU'
{
  "admin/services/smartnet-webhosting": {
    "title": "WebApp Hosting",
    "order": 75,
    "action": { "type": "view", "path": "smartnet/webhosting" },
    "depends": { "acl": [ "luci-app-smartnet-webhosting" ] }
  }
}
MENU

cat > "$LUCI_ACL" <<'ACL'
{
  "luci-app-smartnet-webhosting": {
    "description": "Smart-Net WebApp Hosting status page",
    "read": {
      "ubus": {
        "system": [ "board", "info" ]
      }
    }
  }
}
ACL

cat > "$LUCI_VIEW" <<'VIEW'
'use strict';
'require view';
'require rpc';
'require dom';

var callSystemInfo = rpc.declare({
    object: 'system',
    method: 'info',
    expect: { }
});

var callBoard = rpc.declare({
    object: 'system',
    method: 'board',
    expect: { }
});

return view.extend({
    load: function() {
        return Promise.all([
            callSystemInfo().catch(function() { return {}; }),
            callBoard().catch(function() { return {}; })
        ]);
    },

    render: function(data) {
        var info = data[0] || {};
        var board = data[1] || {};
        var wrap = E('div', { 'class': 'cbi-map' }, [
            E('h2', _('Smart-Net WebApp Hosting')),
            E('p', {}, _('Hosting foundation for AmirNote and future Smart-Net web applications.')),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('System')),
                E('p', {}, _('Model: ') + (board.model || _('Unknown'))),
                E('p', {}, _('Architecture: ') + (board.system || _('Unknown'))),
                E('p', {}, _('Memory total: ') + (info.memory && info.memory.total ? Math.round(info.memory.total / 1048576) + ' MiB' : _('Unknown')))
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('Web server')),
                E('p', {}, _('Nginx site listener: http://192.168.12.1:8080/')),
                E('p', {}, _('LuCI remains on its existing uHTTPd ports.')),
                E('p', {}, _('Frontend root: /home/smartnet/webhosting/sites/amirnote')),
                E('p', {}, _('API upstream: 127.0.0.1:3000 (reserved; runtime not installed)'))
            ]),
            E('div', { 'class': 'cbi-section' }, [
                E('h3', _('AmirNote deployment')),
                E('p', {}, _('The current AmirNote API depends on Vercel Functions and Vercel Blob. A compatible API adapter and storage configuration are required before full operation.')),
                E('p', {}, _('Do not copy BLOB_READ_WRITE_TOKEN into frontend files.'))
            ])
        ]);

        return Promise.resolve(wrap);
    },

    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
VIEW

# LuCI view package is served directly from /www. Reload rpcd/uhttpd only if init exists.
[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
[ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd reload >/dev/null 2>&1 || true

# Runtime probe; never auto-install from an unofficial feed or foreign ABI.
if have node; then
    report "08-webhosting: Node.js executable found: $(node --version 2>/dev/null || echo unknown)"
else
    report "08-webhosting: Node.js unavailable in PATH; AmirNote API runtime not installed"
fi

report "08-webhosting: Nginx installed/configured on tcp/8080; LuCI menu installed; persistent web root=$WEBROOT"
report "08-webhosting: AmirNote frontend deployment pending; API requires Vercel-compatible runtime/storage adapter"
log "Web-hosting foundation installed. Nginx is isolated on :8080; LuCI/uHTTPd ports unchanged."
