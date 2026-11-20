#!/bin/sh
# Mihomo LuCI package deployment is handled at image-build time.
# Runtime Bootstrap must not install a second Mihomo core or overwrite
# the package-owned procd service.
set -eu
REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
log() { printf '[09-mihomo-luci] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }

if apk info -e mihomo >/dev/null 2>&1 && apk info -e luci-app-mihomo >/dev/null 2>&1; then
    report "09-mihomo-luci: managed Mihomo core and LuCI package installed"
    log "Managed Mihomo package pair detected."
elif command -v mihomo >/dev/null 2>&1; then
    report "09-mihomo-luci: standalone Mihomo binary detected; LuCI managed package pair is not installed"
    log "Standalone Mihomo binary detected. No competing service will be installed at runtime."
else
    report "09-mihomo-luci: Mihomo core and LuCI package are not installed"
    log "Mihomo package pair is absent; no runtime feed changes made."
fi
report "09-mihomo-luci: routing, firewall, DNS and proxy service state left unchanged"
