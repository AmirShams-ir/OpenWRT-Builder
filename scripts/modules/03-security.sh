#!/bin/sh
# Security baseline without replacing firewall or SSH policy.
set -eu
PATH="/usr/sbin:/usr/bin:/sbin:/bin"; export PATH
log() { printf '[03-security] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
# fw4/nftables + UCI are OpenWrt-native. Never install UFW or rewrite policy.
if [ -x /etc/init.d/firewall ]; then
 /etc/init.d/firewall enable >/dev/null 2>&1 || true
 report "03-security: existing firewall service enabled; rules unchanged"
else report "03-security: firewall init script not found"; fi
if command -v uci >/dev/null 2>&1; then
 if ! uci -q get system.@system[0].log_size >/dev/null 2>&1; then
  uci set system.@system[0].log_size='64' 2>/dev/null || true
  uci commit system 2>/dev/null || true
 fi
fi
[ ! -x /etc/init.d/log ] || /etc/init.d/log enable >/dev/null 2>&1 || true
report "03-security: OpenWrt logd checked; no UFW/systemd/journald assumptions"
log "Firewall rules and remote access policy preserved."
