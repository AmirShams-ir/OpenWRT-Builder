#!/bin/sh
# Smart-Net proxy stack installer for OpenWrt 25.12 / apk.
# Installs trusted-feed proxy cores, verified Mihomo, and fetches official
# PassWall2 source for later packaging. Does not enable services or alter
# routing, firewall, DNS, WAN/LAN, or wireless configuration.

set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
PASSWALL2_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall2.git"
PASSWALL_PACKAGES_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"
PASSWALL2_SOURCE_DIR="/home/smartnet/sources/passwall2"
PASSWALL_PACKAGES_SOURCE_DIR="/home/smartnet/sources/passwall-packages"
MIHOMO_RELEASE="v1.19.34"
MIHOMO_I386_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_RELEASE}/mihomo-linux-386-${MIHOMO_RELEASE}.gz"
MIHOMO_I386_SHA256="035c37e926a396bffacf4109caab451df891b8c32978238f3757e2b788715287"

log() { printf '[06-proxy-stack] %s\\n' "$*"; }
report() { printf '%s\\n' "$*" >> "$REPORT"; }
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
    command -v gzip >/dev/null 2>&1 || {
        report "06-proxy-stack: Mihomo skipped; gzip missing"
        log "Mihomo skipped: gzip is not installed"
        return 1
    }

    tmp="/tmp/smartnet-mihomo-$$"
    mkdir -p "$tmp"
    trap 'rm -rf "$tmp"' 0 HUP INT TERM

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
    if ! gzip -t "$tmp/mihomo.gz"; then
        report "06-proxy-stack: Mihomo gzip archive invalid"
        log "Mihomo archive is invalid"
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

    # BusyBox on OpenWrt does not provide GNU 'install'. Use cp + chmod.
    # Verify the final binary before reporting successful installation.
    if ! cp "$tmp/mihomo" /usr/bin/mihomo; then
        report "06-proxy-stack: Mihomo copy to /usr/bin failed"
        log "Mihomo installation failed while copying binary"
        return 1
    fi
    if ! chmod 0755 /usr/bin/mihomo; then
        rm -f /usr/bin/mihomo
        report "06-proxy-stack: Mihomo chmod failed"
        log "Mihomo installation failed while setting permissions"
        return 1
    fi
    if [ ! -x /usr/bin/mihomo ] || ! /usr/bin/mihomo -v >/dev/null 2>&1; then
        rm -f /usr/bin/mihomo
        report "06-proxy-stack: Mihomo final execution verification failed"
        log "Mihomo final verification failed; invalid binary removed"
        return 1
    fi

    version="$(/usr/bin/mihomo -v 2>&1 | head -n 1)"
    report "06-proxy-stack: Mihomo installed and verified from official release: $version"
    log "Mihomo installed and verified: $version"
    rm -rf "$tmp"
    trap - 0 HUP INT TERM
    return 0
}

fetch_git_source() {
    repo="$1"
    dest="$2"
    label="$3"

    command -v git >/dev/null 2>&1 || {
        report "06-proxy-stack: $label source fetch skipped; git missing"
        log "$label source fetch skipped: git is not installed"
        return 1
    }
    mkdir -p "$(dirname "$dest")"

    if [ -d "$dest/.git" ]; then
        log "Updating official $label source in $dest"
        if git -C "$dest" pull --ff-only; then
            report "06-proxy-stack: official $label source updated: $dest"
            return 0
        fi
        report "06-proxy-stack: official $label source update failed; existing checkout retained: $dest"
        log "$label source update failed; preserving existing checkout"
        return 1
    fi

    if [ -e "$dest" ]; then
        report "06-proxy-stack: $label source destination exists but is not a Git checkout: $dest"
        log "$label source destination is occupied; refusing overwrite: $dest"
        return 1
    fi

    log "Cloning official $label source from GitHub"
    if git clone --depth 1 "$repo" "$dest"; then
        report "06-proxy-stack: official $label source cloned: $dest"
        return 0
    fi
    rm -rf "$dest"
    report "06-proxy-stack: official $label source clone failed"
    log "$label source clone failed"
    return 1
}

target="$(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_TARGET:-unknown}")"
arch="$(uname -m 2>/dev/null || echo unknown)"
apk_arch="$(apk --print-arch 2>/dev/null || echo unknown)"
report "06-proxy-stack: target=$target arch=$arch apk_arch=$apk_arch"

# Install cores only from the router's currently configured trusted feeds.
install_core sing-box || true
install_core xray-core || true
# Tiny is an alternative sing-box build, not an additional independent core.
discover_only sing-box-tiny

# Mihomo upstream publishes a matching linux/386 binary for this 32-bit x86 box.
case "$arch" in
    i386|i486|i586|i686)
        if [ -x /usr/bin/mihomo ] && /usr/bin/mihomo -v >/dev/null 2>&1; then
            version="$(/usr/bin/mihomo -v 2>&1 | head -n 1)"
            report "06-proxy-stack: Mihomo already installed and executable: $version"
            log "Mihomo already installed: $version"
        else
            install_mihomo_i386 || true
        fi
        ;;
    *)
        report "06-proxy-stack: Mihomo automatic binary install skipped for arch=$arch"
        log "Mihomo automatic binary install skipped for unsupported arch=$arch"
        ;;
esac

# PassWall2 is a LuCI management application, not a proxy core.
# Fetch official upstream source into dedicated /home/smartnet directories.
# Do not install unsigned packages, import keys, or change APK feeds.
if package_installed luci-app-passwall2; then
    report "06-proxy-stack: PassWall2 LuCI package already installed"
    log "PassWall2 LuCI package already installed"
else
    discover_only luci-app-passwall2
    fetch_git_source "$PASSWALL2_REPO" "$PASSWALL2_SOURCE_DIR" "PassWall2" || true
    fetch_git_source "$PASSWALL_PACKAGES_REPO" "$PASSWALL_PACKAGES_SOURCE_DIR" "PassWall2 dependency" || true
    if [ -f "$PASSWALL2_SOURCE_DIR/luci-app-passwall2/Makefile" ]; then
        report "06-proxy-stack: PassWall2 Makefile found; source fetched but not installed"
        log "Official PassWall2 source is present; build it or install from a signed compatible APK feed"
    else
        report "06-proxy-stack: PassWall2 source checkout incomplete or Makefile missing"
        log "PassWall2 source checkout is incomplete; see report"
    fi
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
if [ -x /usr/bin/mihomo ] && /usr/bin/mihomo -v >/dev/null 2>&1; then
    version="$(/usr/bin/mihomo -v 2>&1 | head -n 1)"
    report "06-proxy-stack: Mihomo executable verified: $version"
    log "Mihomo executable verified: $version"
fi

report "06-proxy-stack: no proxy service enabled and no routing/firewall/network configuration changed"
log "Proxy stack module completed; proxy services remain disabled."
