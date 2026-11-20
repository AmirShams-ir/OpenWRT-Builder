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
command -v fdisk >/dev/null 2>&1 || die "fdisk missing; rebuild image with fdisk."
command -v block >/dev/null 2>&1 || die "block-mount missing; rebuild image."
command -v blockdev >/dev/null 2>&1 || die "blockdev missing."
command -v blkid >/dev/null 2>&1 || die "blkid missing."
command -v mkfs.ext4 >/dev/null 2>&1 || die "e2fsprogs missing; rebuild image."
command -v uci >/dev/null 2>&1 || die "uci missing."
command -v awk >/dev/null 2>&1 || die "awk missing."
command -v sfdisk >/dev/null 2>&1 || die "sfdisk missing; add fdisk/sfdisk package."

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
ROOT_SOURCE="$(awk '$2=="/"{print $1; exit}' /proc/mounts)"
[ "$ROOT_SOURCE" = "/dev/root" ] || die "Unexpected root mount source: ${ROOT_SOURCE:-none}."
CMDLINE="$(cat /proc/cmdline)"
case "$CMDLINE" in
  *"root=PARTUUID="*|*"root=UUID="*|*"root=/dev/sda2"*) ;;
  *) die "Cannot confirm root partition 2 from kernel command line." ;;
esac

# Gather current partition metadata from /proc/partitions and sysfs.
# These are independent of human-readable fdisk formatting.
PART1="${DISK}1"
PART2="${DISK}2"
[ -e "/sys/class/block/$(basename "$PART1")/start" ] || die "Partition 1 sysfs data missing."
[ -e "/sys/class/block/$(basename "$PART2")/start" ] || die "Partition 2 sysfs data missing."
DISK_SECTORS="$(blockdev --getsz "$DISK")"
P2_START="$(cat "/sys/class/block/$(basename "$PART2")/start")"
P2_SIZE="$(cat "/sys/class/block/$(basename "$PART2")/size")"
case "$DISK_SECTORS:$P2_START:$P2_SIZE" in *[!0-9:]*|:*|*::*) die "Cannot read disk/partition sector data.";; esac
[ "$DISK_SECTORS" -gt 0 ] || die "Invalid disk capacity."

if [ -b "$PART" ]; then
  log "$PART already exists. It will not be formatted or resized."
  TYPE="$(blkid -s TYPE -o value "$PART" 2>/dev/null || true)"
  [ "$TYPE" = "ext4" ] || die "Existing $PART is not ext4; refusing to format."
else
  # No other partition number may exist. Partitions 1 and 2 must remain exact.
  if printf '%s\n' "$TABLE" | grep -Eq "^${DISK}[3-9][0-9]*[[:space:]]*="; then
    die "Unexpected partition after partition 2; refusing to change disk."
  fi

  P2_START="$(printf '%s\n' "$TABLE" | awk -v p="${DISK}2" '$1==p {gsub(/;/,"",$4); print $4; exit}')"
  P2_SIZE="$(printf '%s\n' "$TABLE" | awk -v p="${DISK}2" '$1==p {for(i=1;i<=NF;i++) if($i ~ /^size=/){sub(/^size=/,"",$i);gsub(/;/,"",$i);print $i;exit}}')"
  case "$P2_START:$P2_SIZE" in *[!0-9:]*|:|*:) die "Cannot parse partition 2 start/size.";; esac
  P2_END=$((P2_START + P2_SIZE - 1))
  START=$(( (P2_END + 1 + 2047) / 2048 * 2048 ))
  [ "$START" -lt "$DISK_SECTORS" ] || die "No free space after partition 2."
  [ $((DISK_SECTORS - START)) -ge 8192 ] || die "Remaining tail is too small for Home."

  log "Creating $PART from sector $START to the final disk sector."
  printf 'label: dos\nlabel-id: 0x%08x\ndevice: %s\nunit: sectors\n\n' 0 "$DISK" > /tmp/installer99.sfdisk
  printf '%s\n' "$TABLE" | awk -v p1="${DISK}1" -v p2="${DISK}2" '$1==p1 || $1==p2 {print}' >> /tmp/installer99.sfdisk
  printf '%s : start=%s, type=83\n' "$PART" "$START" >> /tmp/installer99.sfdisk
  sfdisk --no-reread "$DISK" < /tmp/installer99.sfdisk || die "sfdisk failed; partitions were not intentionally reformatted."
  rm -f /tmp/installer99.sfdisk
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
