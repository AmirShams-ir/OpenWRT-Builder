
#!/bin/sh
# Smart-Net: WireGuard compatibility and installation
# No keys, tunnels, or network configuration are created.

set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"

log() {
    printf '[05-wireguard] %s\n' "$*"
}

report() {
    printf '%s\n' "$*" >> "$REPORT"
}

check_package() {
    pkg="$1"

    # Check whether the package is already installed.
    if apk info -e "$pkg" >/dev/null 2>&1; then
        report "05-wireguard: installed: $pkg"
        return 0
    fi

    # Check repository availability before attempting installation.
    if ! apk search -x "$pkg" 2>/dev/null | grep -q .; then
        report "05-wireguard: unavailable in configured feeds: $pkg"
        return 1
    fi

    # Install only when the package is not already installed.
    if apk add "$pkg" >/dev/null 2>&1; then
        if apk info -e "$pkg" >/dev/null 2>&1; then
            report "05-wireguard: installation successful: $pkg"
            return 0
        fi
    fi

    report "05-wireguard: installation failed: $pkg"
    return 1
}

TOOLS_OK=0
KMOD_OK=0

check_package wireguard-tools && TOOLS_OK=1 || true
check_package kmod-wireguard && KMOD_OK=1 || true

if [ "$TOOLS_OK" -eq 1 ] && command -v wg >/dev/null 2>&1; then
    log "WireGuard userspace tools available: $(wg --version)"
else
    log "WireGuard userspace tools unavailable"
fi

if [ "$KMOD_OK" -eq 1 ]; then
    if [ ! -d /sys/module/wireguard ]; then
        if command -v modprobe >/dev/null 2>&1; then
            modprobe wireguard 2>/dev/null || true
        fi
    fi

    if [ -d /sys/module/wireguard ]; then
        report "05-wireguard: kernel module loaded"
        log "WireGuard kernel module loaded"
    else
        report "05-wireguard: kernel module not loaded"
        log "WireGuard kernel module not loaded"
    fi
fi

log "WireGuard checks completed; no tunnel or network configuration changed."
