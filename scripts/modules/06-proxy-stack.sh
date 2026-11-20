#!/bin/sh
# Smart-Net proxy stack installer for OpenWrt 25.12 / apk.
# Installs official-feed cores and discovers optional PassWall2/Mihomo
# from trusted sources. It never enables proxy services or changes routing.

set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
PASSWALL2_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall2.git"
PASSWALL_PACKAGES_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"
MIHOMO_RELEASE="v1.19.34"
MIHOMO_I386_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_RELEASE}/mihomo-linux-386-${MIHOMO_RELEASE}.gz"
MIHOMO_I386_SHA256="035c37e926a396bffacf4109caab451df891b8c32978238f3757e2b788715287"

log() { printf '[06-proxy-stack] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }
package_installed() { apk info -e "$1" >/dev/null 2>&1; }
package_available() { apk search -x "$1" 2>/dev/null | grep -q .; }

install_core() {
    pkg="$1"
    if package_installed "$pkg"; then
        report "06-proxy-stack: installed: $pkg"
        log "$pkg is already installed"
        return 0
    fi
    if ! package_available "$pkg"; then
        report "06-proxy-stack: unavailable in configured trusted feeds: $pkg"
        log "$pkg is unavailable in configured feeds"
        return 1
    fi
    log "Installing $pkg"
    if apk add "$pkg" >/dev/null 2>&1 && package_installed "$pkg"; then
        report "06-proxy-stack: installation successful: $pkg"
        log "$pkg installed successfully"
        return 0
    fi
    report "06-proxy-stack: installation failed: $pkg"
    log "Installation failed for $pkg"
    return 1
}

discover_only() {
    pkg="$1"
    if package_installed "$pkg"; then
        report "06-proxy-stack: already installed (not modified): $pkg"
        log "$pkg is installed; no changes requested"
    elif package_available "$pkg"; then
        report "06-proxy-stack: available (not installed): $pkg"
        log "$pkg is available; left uninstalled"
    else
        report "06-proxy-stack: unavailable in configured feeds: $pkg"
        log "$pkg is unavailable in configured feeds"
    fi
}

install_mihomo_i386() {
    command -v curl >/dev/null 2>&1 || {
        report "06-proxy-stack: Mihomo skipped; curl missing"
        log "Mihomo skipped: curl is not installed"
        return 1
    }
    command -v sha256sum >/dev/null 2>&1 || {
        report "06-proxy-stack: Mihomo skipped; sha256sum missing"
        log "Mihomo skipped: sha256sum is not installed"
        return 1
    }

    tmp="/tmp/smartnet-mihomo-$$"
    mkdir -p "$tmp"
    trap 'rm -rf "$tmp"' EXIT HUP INT TERM

    log "Downloading official Mihomo ${MIHOMO_RELEASE} linux/386 release"
    if ! curl -fL --connect-timeout 20 --max-time 180 "$MIHOMO_I386_URL" -o "$tmp/mihomo.gz"; then
        report "06-proxy-stack: Mihomo download failed"
        log "Mihomo download failed"
        return 1
    fi

    actual="$(sha256sum "$tmp/mihomo.gz" | awk '{print $1}')"
    if [ "$actual" != "$MIHOMO_I386_SHA256" ]; then
        report "06-proxy-stack: Mihomo checksum mismatch; binary not installed"
        log "Mihomo checksum mismatch; refusing installation"
        return 1
    fi

    if ! command -v gzip >/dev/null 2>&1 || ! gzip -t "$tmp/mihomo.gz"; then
        report "06-proxy-stack: Mihomo archive invalid or gzip unavailable"
        log "Mihomo archive invalid or gzip unavailable"
        return 1
    fi
    if ! gzip -dc "$tmp/mihomo.gz" > "$tmp/mihomo"; then
        report "06-proxy-stack: Mihomo extraction failed"
        log "Mihomo extraction failed"
        return 1
    fi
    chmod 0755 "$tmp/mihomo"
    if ! "$tmp/mihomo" -v >/dev/null 2>&1; then
        report "06-proxy-stack: Mihomo linux/386 binary execution test failed"
        log "Mihomo binary did not pass execution test"
        return 1
    fi

    install -m 0755 "$tmp/mihomo" /usr/bin/mihomo
    version="$(/usr/bin/mihomo -v 2>&1 | head -n 1 || true)"
    report "06-proxy-stack: Mihomo installed from official release: $version"
    log "Mihomo installed and verified: $version"
    rm -rf "$tmp"
    trap - EXIT HUP INT TERM
    return 0
}

target="$(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_TARGET:-unknown}")"
arch="$(uname -m 2>/dev/null || echo unknown)"
apk_arch="$(apk --print-arch 2>/dev/null || echo unknown)"
report "06-proxy-stack: target=$target arch=$arch apk_arch=$apk_arch"

# Core packages from the configured, signed OpenWrt package repositories.
install_core sing-box || true
install_core xray-core || true
# Tiny is an alternative sing-box build, not an additional independent core.
discover_only sing-box-tiny

# Mihomo upstream publishes a matching linux/386 binary. Install it only on
# 32-bit x86; do not accidentally install amd64/arm binaries on the Atom N270.
case "$arch" in
    i386|i486|i586|i686)
        if [ -x /usr/bin/mihomo ]; then
            log "Mihomo binary already exists; checking it"
            if /usr/bin/mihomo -v >/dev/null 2>&1; then
                report "06-proxy-stack: Mihomo already installed and executable"
            else
                report "06-proxy-stack: existing Mihomo binary is not executable"
            fi
        else
            install_mihomo_i386 || true
        fi
        ;;
    *)
        report "06-proxy-stack: Mihomo automatic binary install skipped for arch=$arch"
        log "Mihomo automatic binary install skipped for unsupported arch=$arch"
        ;;
esac

# PassWall2 is LuCI integration, not a proxy core. Its source and dependencies
# are maintained in separate upstream repositories. Do not clone/build them
# on the live router or add unverified package feeds from this module.
if package_installed luci-app-passwall2; then
    report "06-proxy-stack: PassWall2 LuCI package already installed"
    log "PassWall2 LuCI package already installed"
else
    discover_only luci-app-passwall2
    report "06-proxy-stack: PassWall2 source: $PASSWALL2_REPO"
    report "06-proxy-stack: PassWall2 dependency source: $PASSWALL_PACKAGES_REPO"
    log "PassWall2 source located; package not installed because no signed compatible apk feed is configured"
fi

if command -v sing-box >/dev/null 2>&1; then
    version="$(sing-box version 2>/dev/null | head -n 1 || true)"
    report "06-proxy-stack: sing-box executable: ${version:-version unavailable}"
    log "sing-box executable: ${version:-version unavailable}"
fi
if command -v xray >/dev/null 2>&1; then
    version="$(xray version 2>/dev/null | head -n 1 || true)"
    report "06-proxy-stack: Xray executable: ${version:-version unavailable}"
    log "Xray executable: ${version:-version unavailable}"
fi
if [ -x /usr/bin/mihomo ]; then
    version="$(/usr/bin/mihomo -v 2>&1 | head -n 1 || true)"
    report "06-proxy-stack: Mihomo executable: ${version:-version unavailable}"
    log "Mihomo executable: ${version:-version unavailable}"
fi

report "06-proxy-stack: no proxy service enabled and no routing/firewall/network configuration changed"
log "Proxy core discovery/installation completed; services remain disabled."
