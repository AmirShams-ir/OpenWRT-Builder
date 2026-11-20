#!/bin/sh
# Optional WireGuard package compatibility check. No keys/interfaces are created.
set -eu
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
for pkg in wireguard-tools kmod-wireguard; do
 if apk add "$pkg" >/dev/null 2>&1; then report "05-wireguard: available/installed $pkg"
 else report "05-wireguard: unavailable for current target/feed: $pkg"; fi
done
command -v wg >/dev/null 2>&1 && echo '[05-wireguard] wg command available' || echo '[05-wireguard] wg command unavailable'
