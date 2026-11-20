#!/bin/sh
# Smart-Net: conservative proxy-stack package selection.
# sing-box is the default core. Other cores are discovery-only.
# Never add third-party feeds or install unsigned binaries.
set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"

log() {
    printf '[06-proxy-stack] %s\n' "$*"
}

report() {
    printf '%s\n' "$*" >> "$REPORT"
}

package_installed() {
    apk info -e "$1" >/dev/null 2>&1
}

package_available() {
    apk search -x "$1" 2>/dev/null | grep -q .
}

install_selected_core() {
    pkg="$1"

    if package_installed "$pkg"; then
        report "06-proxy-stack: installed: $pkg"
        log "$pkg is already installed"
        return 0
    fi

    if ! package_available "$pkg"; then
        report "06-proxy-stack: unavailable in configured trusted feeds: $pkg"
        log "$pkg is not available in configured feeds"
        return 1
    fi

    if apk add "$pkg" >/dev/null 2>&1 && package_installed "$pkg"; then
        report "06-proxy-stack: installation successful: $pkg"
        log "$pkg installed successfully"
        return 0
    fi

    report "06-proxy-stack: installation failed: $pkg"
    log "installation failed for $pkg"
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
        report "06-proxy-stack: unavailable in configured trusted feeds: $pkg"
        log "$pkg is unavailable in configured feeds"
    fi
}

arch="$(uname -m 2>/dev/null || echo unknown)"
target="$(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_TARGET:-unknown}")"
report "06-proxy-stack: arch=$arch target=$target"
report "06-proxy-stack: default core=sing-box"

# Install only the selected default core. Never install multiple cores implicitly.
install_selected_core sing-box || true

# Discovery-only packages: do not install these automatically.
discover_only sing-box-tiny
discover_only xray-core
discover_only mihomo
discover_only passwall2
discover_only luci-app-passwall2

if command -v sing-box >/dev/null 2>&1; then
    version="$(sing-box version 2>/dev/null | head -n 1 || true)"
    report "06-proxy-stack: sing-box command available: ${version:-version unavailable}"
    log "sing-box command available: ${version:-version unavailable}"
else
    report "06-proxy-stack: sing-box command unavailable"
    log "sing-box command unavailable"
fi

report "06-proxy-stack: no third-party feed, unsigned binary, service, or network configuration added"
log "Proxy package checks completed; only sing-box is eligible for automatic installation."
