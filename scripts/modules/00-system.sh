#!/bin/sh
# Base utilities, package metadata, timezone/NTP, and platform facts.
set -eu
PATH="/usr/sbin:/usr/bin:/sbin:/bin"; export PATH
log() { printf '[00-system] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
apk update || { log "WARNING: apk index refresh failed; using cached indexes."; report "00-system: apk update failed"; }
for pkg in ca-bundle curl wget-ssl ip-full ethtool tcpdump; do
 if ! apk add "$pkg" >/dev/null 2>&1; then report "00-system: unavailable package $pkg"; fi
done
# OpenWrt uses procd/sysntpd, not systemd/chrony by default.
if [ -x /etc/init.d/sysntpd ]; then
 /etc/init.d/sysntpd enable >/dev/null 2>&1 || true
 /etc/init.d/sysntpd restart >/dev/null 2>&1 || true
 report "00-system: sysntpd enabled"
else report "00-system: sysntpd init script not found"; fi
# Preserve configured timezone and NTP servers.
if command -v uci >/dev/null 2>&1; then
 tz="$(uci -q get system.@system[0].timezone 2>/dev/null || true)"
 if [ -z "$tz" ]; then
  uci -q set system.@system[0].zonename='UTC' 2>/dev/null || true
  uci -q set system.@system[0].timezone='UTC' 2>/dev/null || true
  uci -q commit system 2>/dev/null || true
 fi
fi
. /etc/openwrt_release
report "00-system: release ${DISTRIB_DESCRIPTION:-unknown}; kernel $(uname -r); arch $(uname -m)"
log "Base system checks completed; network configuration untouched."
