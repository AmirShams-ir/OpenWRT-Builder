#!/bin/sh
# Read-only Nikki/Mihomo audit. Never enable service, edit UCI, or reload fw4.
set -eu
REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
log() { printf '[09-mihomo-luci] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }
installed() { apk info -e "$1" >/dev/null 2>&1; }
if installed mihomo-meta && installed nikki && installed luci-app-nikki; then
  enabled="$(uci -q get nikki.config.enabled 2>/dev/null || echo 0)"
  report "09-mihomo-luci: installed mihomo-meta, nikki, luci-app-nikki"
  report "09-mihomo-luci: nikki.config.enabled=${enabled:-0}"
  log "Nikki package set detected; service switch is ${enabled:-0}."
elif installed mihomo-meta || installed nikki || installed luci-app-nikki; then
  report "09-mihomo-luci: incomplete Nikki package set"
  log "Incomplete Nikki package set detected; no repair attempted."
else
  report "09-mihomo-luci: Nikki package set absent"
  log "Nikki package set absent."
fi
if uci -q get firewall.nikki >/dev/null 2>&1; then
  report "09-mihomo-luci: firewall.nikki include exists"
else
  report "09-mihomo-luci: firewall.nikki include absent"
fi
report "09-mihomo-luci: no service/UCI/firewall/routing/DNS/network changes performed"
