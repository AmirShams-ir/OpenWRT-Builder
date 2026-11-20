#!/bin/sh
# Smart-Net: install all compatible proxy cores available in trusted feeds.
# sing-box-tiny is an alternative build of sing-box and is not installed
# alongside the full sing-box package. No third-party feeds or unsigned
# binaries are added.
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
        report "06-proxy-stack: unavailable in configured trusted feeds: $pkg"
        log "$pkg is unavailable in configured feeds"
    fi
}

arch="$(uname -m 2>/dev/null || echo unknown)"
target="$(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_TARGET:-unknown}")"
report "06-proxy-stack: arch=$arch target=$target"
report "06-proxy-stack: installing all available independent proxy cores"

# Install every independent core available from the currently configured feeds.
# Failures are reported but do not prevent trying the remaining cores.
install_core sing-box || true
install_core xray-core || true

# sing-box-tiny provides the same sing-box command/version as the full build.
# It is an alternative package, not an additional independent core.
discover_only sing-box-tiny

# These packages are not present in the current official feeds; only report
# availability. Never add an unreviewed custom feed automatically.
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

if command -v xray >/dev/null 2>&1; then
    report "06-proxy-stack: Xray command available"
    log "Xray command available"
elif command -v xray-core >/dev/null 2>&1; then
    report "06-proxy-stack: Xray core command available"
    log "Xray core command available"
else
    report "06-proxy-stack: Xray command not found after package check"
fi

report "06-proxy-stack: no third-party feed, unsigned binary, service, or network configuration added"
log "Proxy core installation and discovery completed."
