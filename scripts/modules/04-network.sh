#!/bin/sh
# Diagnostics only: never edits WAN/LAN/Wi-Fi/DHCP/DNS.
set -eu
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
if command -v ip >/dev/null 2>&1; then
 report "04-network: links: $(ip link 2>/dev/null | tr '\n' ';')"
 report "04-network: addresses: $(ip address 2>/dev/null | tr '\n' ';')"
fi
report "04-network: network UCI, wireless, DHCP and DNS intentionally unchanged"
printf '[04-network] Network inspection completed; configuration untouched.\n'
