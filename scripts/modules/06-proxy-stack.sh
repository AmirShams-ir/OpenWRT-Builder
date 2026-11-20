#!/bin/sh
# Optional proxy package discovery. Do not add third-party feeds or unsigned binaries.
set -eu
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
arch="$(uname -m 2>/dev/null || echo unknown)"
target="$(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_TARGET:-unknown}")"
report "06-proxy-stack: arch=$arch target=$target"
for pkg in sing-box xray-core mihomo passwall2 luci-app-passwall2; do
 if apk add "$pkg" >/dev/null 2>&1; then report "06-proxy-stack: installed/available $pkg"
 else report "06-proxy-stack: unavailable in configured trusted feeds: $pkg"; fi
done
report "06-proxy-stack: no third-party feed or unsigned binary added"
echo '[06-proxy-stack] Proxy compatibility checks completed.'
