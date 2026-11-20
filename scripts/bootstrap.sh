#!/bin/sh
# Smart-Net Bootstrap orchestrator for OpenWrt 25.12+
# Storage layout is exclusively managed by Installer99.
set -eu
PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
MODULE_DIR="$ROOT_DIR/scripts/modules"
LOG_FILE="/var/log/smartnet-bootstrap.log"
LOCK_DIR="/var/lock/smartnet-bootstrap.lock"
REPORT_FILE="/root/smartnet-bootstrap-report.txt"
MODULES="00-system.sh 01-memory.sh 02-kernel.sh 03-security.sh 04-network.sh 05-wireguard.sh 06-proxy-stack.sh 07-docker.sh 08-webhosting.sh 09-mihomo-luci.sh"
log() {
  line="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo time-unknown) [Bootstrap] $*"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
}
die() { log "ERROR: $*"; exit 1; }
[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -r /etc/openwrt_release ] || die "This does not appear to be OpenWrt."
[ -d "$MODULE_DIR" ] || die "Missing module directory: $MODULE_DIR"
command -v apk >/dev/null 2>&1 || die "OpenWrt apk package manager was not found."
mkdir -p /var/lock /var/log
if ! mkdir "$LOCK_DIR" 2>/dev/null; then die "Another Bootstrap process is running."; fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT HUP INT TERM
: > "$LOG_FILE" 2>/dev/null || true
: > "$REPORT_FILE"
printf 'Smart-Net Bootstrap report\nGenerated: %s\n\n' "$(date 2>/dev/null || true)" >> "$REPORT_FILE"
. /etc/openwrt_release
ARCH="$(uname -m 2>/dev/null || echo unknown)"
BOARD="$(cat /tmp/sysinfo/board_name 2>/dev/null || echo unknown)"
MODEL="$(cat /tmp/sysinfo/model 2>/dev/null || echo unknown)"
MEM_KB="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
log "Starting on ${DISTRIB_DESCRIPTION:-OpenWrt}; board=$BOARD; model=$MODEL; arch=$ARCH; RAM=${MEM_KB}KiB"
{
 echo "Release: ${DISTRIB_DESCRIPTION:-unknown}"
 echo "Target: ${DISTRIB_TARGET:-unknown}"
 echo "Board: $BOARD"
 echo "Model: $MODEL"
 echo "Architecture: $ARCH"
 echo "RAM KiB: $MEM_KB"
 echo "Kernel: $(uname -r)"
} >> "$REPORT_FILE"
export SMARTNET_ROOT_DIR="$ROOT_DIR" SMARTNET_MODULE_DIR="$MODULE_DIR"
export SMARTNET_REPORT_FILE="$REPORT_FILE" SMARTNET_LOG_FILE="$LOG_FILE"
for module in $MODULES; do
 path="$MODULE_DIR/$module"
 [ -f "$path" ] || { log "SKIP missing module: $module"; continue; }
 log "Running module: $module"
 if sh "$path"; then log "OK: $module"
 else rc=$?; printf '%s: FAILED (exit %s)\n' "$module" "$rc" >> "$REPORT_FILE"; log "ERROR: $module failed (exit $rc); continuing."; fi
done
log "Bootstrap finished. Detailed report: $REPORT_FILE"
cat "$REPORT_FILE"
