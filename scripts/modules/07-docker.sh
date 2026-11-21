#!/bin/sh
# Smart-Net Module 07: install and configure Docker for Amir-File hosting.
# OpenWrt 25.12+ (APK). Storage layout remains Installer99's responsibility.
set -eu

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
LOG="${SMARTNET_LOG_FILE:-/var/log/smartnet-bootstrap.log}"
DOCKER_ROOT="${SMARTNET_DOCKER_ROOT:-/home/smartnet/docker}"
MIN_RAM_MB="${SMARTNET_DOCKER_MIN_RAM_MB:-1536}"
MIN_FREE_MB="${SMARTNET_DOCKER_MIN_FREE_MB:-2048}"

log() {
    printf '%s\n' "[07-docker] $*"
    printf '%s\n' "[07-docker] $*" >> "$LOG" 2>/dev/null || true
}
report() {
    printf '%s\n' "$*" >> "$REPORT" 2>/dev/null || true
}
fail() {
    log "ERROR: $*"
    report "07-docker: FAILED - $*"
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail "must run as root"
command -v apk >/dev/null 2>&1 || fail "APK package manager not found"
command -v uci >/dev/null 2>&1 || fail "UCI not found"

# Load OpenWrt release metadata for package architecture.
[ ! -r /etc/openwrt_release ] || . /etc/openwrt_release
PKG_ARCH="${DISTRIB_ARCH:-unknown}"
CPU_ARCH="$(uname -m 2>/dev/null || echo unknown)"
MEM_KB="$(awk '/MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)"
MEM_MB=$((MEM_KB / 1024))

log "Target architecture=$PKG_ARCH; CPU architecture=$CPU_ARCH; RAM=${MEM_MB}MiB"

# Atom N270 reports i686 while OpenWrt packages use i386_pentium4.
case "$PKG_ARCH:$CPU_ARCH" in
    i386_pentium4:i686|i386_pentium4:x86_64|x86_64:x86_64|\
    aarch64*:aarch64|arm_*:arm*|*) : ;;
esac

if [ "$MEM_MB" -lt "$MIN_RAM_MB" ]; then
    report "07-docker: skipped; RAM ${MEM_MB}MiB is below configured minimum ${MIN_RAM_MB}MiB"
    log "Docker skipped by RAM policy."
    exit 0
fi

# Docker data must live on the dedicated persistent ext4 data partition,
# not on the limited OpenWrt root filesystem.
mountpoint -q /home/smartnet || fail "/home/smartnet is not mounted; refusing to place Docker data on rootfs"
FS_TYPE="$(awk '$2=="/home/smartnet" {print $3; exit}' /proc/mounts)"
[ "$FS_TYPE" = "ext4" ] || fail "/home/smartnet filesystem is '$FS_TYPE', expected ext4"

FREE_KB="$(df -Pk /home/smartnet | awk 'NR==2 {print $4}')"
FREE_MB=$((FREE_KB / 1024))
[ "$FREE_MB" -ge "$MIN_FREE_MB" ] || fail "only ${FREE_MB}MiB free on /home/smartnet; need at least ${MIN_FREE_MB}MiB"

# Refresh APK indexes. This also handles systems where indexes are not cached.
log "Refreshing APK package indexes..."
apk update || fail "apk update failed; check repository connectivity"

# Verify package availability before starting installation. APK resolves all
# declared runtime/kernel dependencies automatically.
for pkg in dockerd docker docker-compose; do
    apk search -x "$pkg" | grep -q "^$pkg-" || fail "required package '$pkg' is unavailable for $PKG_ARCH"
done

log "Installing Docker Engine, CLI, Compose and repository dependencies..."
apk add dockerd docker docker-compose || fail "APK failed to install Docker packages or dependencies"

[ -x /etc/init.d/dockerd ] || fail "dockerd init script was not installed"
[ -f /etc/config/dockerd ] || fail "dockerd UCI configuration was not installed"

# Create persistent data directory on the dedicated ext4 partition.
mkdir -p "$DOCKER_ROOT" || fail "cannot create Docker data directory: $DOCKER_ROOT"
chmod 0711 "$DOCKER_ROOT"

# Configure the OpenWrt dockerd package via UCI, preserving unrelated settings.
uci set dockerd.globals.data_root="$DOCKER_ROOT" || fail "cannot set Docker data-root"
uci commit dockerd || fail "cannot commit Docker UCI configuration"

log "Docker data-root configured as $DOCKER_ROOT"
log "Enabling and starting dockerd..."
/etc/init.d/dockerd enable || fail "could not enable dockerd at boot"
/etc/init.d/dockerd start || fail "dockerd init service failed to start"

# Verify daemon readiness (bounded wait).
READY=0
i=1
while [ "$i" -le 20 ]; do
    if docker info >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 2
    i=$((i + 1))
done

[ "$READY" -eq 1 ] || {
    /etc/init.d/dockerd status >/dev/null 2>&1 || true
    fail "dockerd did not become ready; inspect logread and /etc/config/dockerd"
}

docker version >/dev/null 2>&1 || fail "Docker CLI could not communicate with daemon"
docker-compose version >/dev/null 2>&1 || fail "Docker Compose verification failed"

DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
report "07-docker: installed and running; Docker Engine=$DOCKER_VERSION; data-root=$DOCKER_ROOT; package-arch=$PKG_ARCH"
log "Docker installation and daemon verification completed successfully."
