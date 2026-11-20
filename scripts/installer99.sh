#!/bin/sh
# Smart-Net Installer 99
# Creates only partition 3 in unallocated tail space, formats it ext4,
# and registers a persistent /home mount. It does not install packages.
set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

DISK="${SMARTNET_DISK:-/dev/sda}"
MOUNTPOINT="/home"
LABEL="SMARTNET_HOME"
LOCK="/var/lock/smartnet-installer99.lock"

log() { printf '[Installer99] %s\n' "$*"; }
die() { printf '[Installer99] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -b "$DISK" ] || die "Target disk does not exist: $DISK"
command -v block >/dev/null 2>&1 || die "block-mount missing; rebuild image."
command -v blockdev >/dev/null 2>&1 || die "blockdev missing."
command -v blkid >/dev/null 2>&1 || die "blkid missing."
command -v mkfs.ext4 >/dev/null 2>&1 || die "e2fsprogs missing; rebuild image."
command -v uci >/dev/null 2>&1 || die "uci missing."
command -v awk >/dev/null 2>&1 || die "awk missing."
command -v sfdisk >/dev/null 2>&1 || die "sfdisk missing; add fdisk package."

mkdir -p /var/lock
if ! mkdir "$LOCK" 2>/dev/null; then die "Installer99 is already running."; fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

DISK="$(readlink -f "$DISK")"
case "$DISK" in
  /dev/sd[a-z]|/dev/vd[a-z]) PART="${DISK}3" ;;
  /dev/nvme[0-9]n[0-9]|/dev/mmcblk[0-9]) PART="${DISK}p3" ;;
  *) die "Unsupported disk device: $DISK" ;;
esac

# This installer is explicitly limited to the known BIOS/MBR two-partition
# base image. Never guess when root/boot sources do not match that layout.
BOOT_SOURCE="$(awk '$2=="/boot"{print $1; exit}' /proc/mounts)"
case "$BOOT_SOURCE" in
  "${DISK}1") ;;
  *) die "Expected /boot on ${DISK}1; found ${BOOT_SOURCE:-none}." ;;
esac
CMDLINE="$(cat /proc/cmdline)"
case "$CMDLINE" in
  *"root=PARTUUID="*|*"root=UUID="*|*"root=/dev/sda2"*) ;;
  *) die "Cannot confirm root partition 2 from kernel command line." ;;
esac

# Gather current partition metadata using sysfs (sector units).
PART1="${DISK}1"
PART2="${DISK}2"
[ -e "/sys/class/block/$(basename "$PART1")/start" ] || die "Partition 1 sysfs data missing."
[ -e "/sys/class/block/$(basename "$PART2")/start" ] || die "Partition 2 sysfs data missing."
DISK_SECTORS="$(blockdev --getsz "$DISK")"
P1_START="$(cat "/sys/class/block/$(basename "$PART1")/start")"
P1_SIZE="$(cat "/sys/class/block/$(basename "$PART1")/size")"
P2_START="$(cat "/sys/class/block/$(basename "$PART2")/start")"
P2_SIZE="$(cat "/sys/class/block/$(basename "$PART2")/size")"
case "$DISK_SECTORS:$P1_START:$P1_SIZE:$P2_START:$P2_SIZE" in *[!0-9:]*|:*|*::*) die "Cannot read disk/partition sector data.";; esac
[ "$DISK_SECTORS" -gt 0 ] || die "Invalid disk capacity."

TABLE="$(sfdisk --dump "$DISK" 2>/dev/null)" || die "Cannot read partition table."
printf '%s\\n' "$TABLE" | grep -q '^label: dos$' || die "Expected DOS/MBR partition table."
printf '%s\\n' "$TABLE" | grep -q "^${DISK}1[[:space:]]*=" || die "Partition 1 missing."
printf '%s\\n' "$TABLE" | grep -q "^${DISK}2[[:space:]]*=" || die "Partition 2 missing."
if printf '%s\\n' "$TABLE" | grep -Eq "^${DISK}[3-9][0-9]*[[:space:]]*="; then
  die "Unexpected partition beyond partition 2; refusing to alter disk."
fi

if [ -b "$PART" ]; then
  log "$PART already exists. It will not be formatted or resized."
  TYPE="$(blkid -s TYPE -o value "$PART" 2>/dev/null || true)"
  [ "$TYPE" = "ext4" ] || die "Existing $PART is not ext4; refusing to format."
else
  P2_END=$((P2_START + P2_SIZE - 1))
  START=$(( (P2_END + 1 + 2047) / 2048 * 2048 ))
  [ "$START" -lt "$DISK_SECTORS" ] || die "No unallocated space after partition 2."
  [ $((DISK_SECTORS - START)) -ge 8192 ] || die "Remaining tail is too small for Home."

  log "Creating $PART from sector $START to the final disk sector."
  sfdisk --no-reread "$DISK" <<EOF
label: dos
unit: sectors
${PART1} : start=${P1_START}, size=${P1_SIZE}, type=83
${PART2} : start=${P2_START}, size=${P2_SIZE}, type=83
${PART} : start=${START}, type=83
EOF
  blockdev --rereadpt "$DISK" 2>/dev/null || true
  sleep 2
  [ -b "$PART" ] || die "$PART did not appear after partition-table update."
  mkfs.ext4 -F -L "$LABEL" "$PART"
fi

# Refuse to mount over pre-existing /home content on first initialization.
mkdir -p "$MOUNTPOINT"
if ! awk -v m="$MOUNTPOINT" '$2==m {found=1} END{exit found?0:1}' /proc/mounts; then
  if [ -n "$(ls -A "$MOUNTPOINT" 2>/dev/null || true)" ]; then
    die "$MOUNTPOINT contains files and is not mounted; refusing to hide them."
  fi
else
  CURRENT="$(awk -v m="$MOUNTPOINT" '$2==m {print $1; exit}' /proc/mounts)"
  [ "$CURRENT" = "$PART" ] || die "$MOUNTPOINT is already mounted from $CURRENT."
fi

UUID="$(blkid -s UUID -o value "$PART" 2>/dev/null || true)"
[ -n "$UUID" ] || die "Could not read UUID of $PART."

uci -q delete fstab.smartnet_home 2>/dev/null || true
uci set fstab.smartnet_home='mount'
uci set fstab.smartnet_home.target="$MOUNTPOINT"
uci set fstab.smartnet_home.uuid="$UUID"
uci set fstab.smartnet_home.fstype='ext4'
uci set fstab.smartnet_home.options='rw,noatime'
uci set fstab.smartnet_home.enabled='1'
uci commit fstab

/etc/init.d/fstab enable
/etc/init.d/fstab restart
sleep 2
awk -v m="$MOUNTPOINT" '$2==m {found=1} END{exit found?0:1}' /proc/mounts || die "Home partition did not mount."

log "Success: $PART mounted at $MOUNTPOINT (UUID=$UUID)."
log "Partitions 1 and 2 were not formatted, resized, or intentionally changed."
