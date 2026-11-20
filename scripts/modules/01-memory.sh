#!/bin/sh
# Prefer zram where supported; never create a disk swapfile.
set -eu
PATH="/usr/sbin:/usr/bin:/sbin:/bin"; export PATH
log() { printf '[01-memory] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
[ "$mem_kb" -gt 0 ] || { report "01-memory: unable to read RAM size"; exit 0; }
mem_mb=$((mem_kb / 1024))
log "Detected RAM: ${mem_mb} MiB"
if [ -e /sys/block/zram0 ] || command -v zramctl >/dev/null 2>&1; then
 report "01-memory: zram device/tool already present; left unchanged"
elif apk add zram-swap >/dev/null 2>&1; then
 for init in /etc/init.d/zram /etc/init.d/zram-swap; do
  if [ -x "$init" ]; then "$init" enable >/dev/null 2>&1 || true; "$init" start >/dev/null 2>&1 || true; fi
 done
 report "01-memory: zram-swap package installed; init integration attempted"
else report "01-memory: zram-swap unavailable for target/feed; no swap changes"; fi
if [ -w /proc/sys/vm/swappiness ]; then
 old="$(cat /proc/sys/vm/swappiness 2>/dev/null || echo unknown)"
 echo 60 > /proc/sys/vm/swappiness 2>/dev/null || true
 report "01-memory: swappiness set to 60 (was $old)"
else report "01-memory: swappiness knob unavailable"; fi
log "Memory policy completed without disk swap or partition changes."
