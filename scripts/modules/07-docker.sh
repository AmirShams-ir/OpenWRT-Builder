#!/bin/sh
# Optional Docker runtime, gated for RAM and architecture.
set -eu
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
mem_mb=$((mem_kb / 1024))
arch="$(uname -m 2>/dev/null || echo unknown)"
if [ "$mem_mb" -lt 2048 ]; then
 report "07-docker: skipped; RAM ${mem_mb}MiB is below 2048MiB safety threshold"; exit 0
fi
case "$arch" in x86_64|aarch64|armv7l) ;; *) report "07-docker: skipped; architecture $arch is not allowlisted"; exit 0;; esac
if apk add dockerd docker-cli docker-compose >/dev/null 2>&1; then
 [ ! -x /etc/init.d/dockerd ] || /etc/init.d/dockerd enable >/dev/null 2>&1 || true
 report "07-docker: packages installed; daemon enabled if init script exists, not force-started"
else report "07-docker: packages unavailable for target/repository"; fi
echo '[07-docker] Docker compatibility check completed.'
