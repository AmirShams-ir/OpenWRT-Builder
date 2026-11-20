#!/bin/sh
# Smart-Net Installer 99
# Create partition 3 in unallocated tail space, format ext4, mount /home.
# This script never installs packages and never alters partitions 1 or 2.
set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH
DISK="${SMARTNET_DISK:-/dev/sda}"
PART="${DISK}3"
MOUNTPOINT="/home"
LABEL="SMARTNET_HOME"
LOCK="/var/lock/smartnet-installer99.lock"

log() { printf '[Installer99] %s\n' "$*"; }
die() { printf '[Installer99] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -b "$DISK" ] || die "Target disk does not exist: $DISK"
command -v fdisk >/dev/null 2>&1 || die "fdisk is missing; rebuild image with fdisk."
command -v block >/dev/null 2>&1 || die "block utility missing; rebuild image with block-mount."
command -v blockdev >/dev/null 2>&1 || die "blockdev utility missing."
command -v blkid >/dev/null 2>&1 || die "blkid utility missing."
command -v mkfs.ext4 >/dev/null 2>&1 || die "mkfs.ext4 missing; rebuild image with e2fsprogs."
command -v uci >/dev/null 2>&1 || die "uci missing."
command -v awk >/dev/null 2>&1 || die "awk missing."

mkdir -p /var/lock
if ! mkdir "$LOCK" 2>/dev/null; then die "Installer99 lock exists: $LOCK"; fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM

DISK="$(readlink -f "$DISK")"
case "$DISK" in
  /dev/sd[a-z]|/dev/vd[a-z]|/dev/nvme[0-9]n[0-9]|/dev/mmcblk[0-9]) ;;
  *) die "Unsupported disk device: $DISK" ;;
esac

BOOT_SOURCE="$(awk '$2=="/boot"{print $1; exit}' /proc/mounts)"
case "$BOOT_SOURCE" in
  "${DISK}1"|" ${DISK}p1") ;;
  *) die "Expected /boot on partition 1 of $DISK; found ${BOOT_SOURCE:-none}";;
esac
CMDLINE="$(cat /proc/cmdline)"
case "$CMDLINE" in
  *"root=PARTUUID="*|*"root=UUID="*|*"root=/dev/sda2"*|*"root=/dev/vda2"*) ;;
  *) die "Cannot verify root partition identity from kernel command line.";;
esac

PARTITION_TABLE="$(fdisk -l "$DISK" 2>/dev/null)" || die "Cannot read partition table."
printf '%s\n' "$PARTITION_TABLE" | awk -v p1="${DISK}1" -v p2="${DISK}2" '
  $1==p1 {n1=1}
  $1==p2 {n2=1}
  END {if (!n1 || !n2) exit 1}
' || die "Expected partitions 1 and 2 were not found."

DISK_SECTORS="$(blockdev --getsz "$DISK")"
[ "$DISK_SECTORS" -gt 0 ] || die "Cannot read disk capacity."

if [ -b "$PART" ]; then
  log "$PART already exists; never reformatting it."
  TYPE="$(blkid -s TYPE -o value "$PART" 2>/dev/null || true)"
  [ "$TYPE" = "ext4" ] || die "$PART exists but is not ext4; refusing to format."
else
  if printf '%s\n' "$PARTITION_TABLE" | awk -v d="$DISK" '
    $1 ~ ("^" d "[0-9]+$") && $1 != d "1" && $1 != d "2" {bad=1}
    END {exit bad ? 0 : 1}
  '; then
    die "Unexpected partition(s) beyond partition 2; refusing to modify disk."
  fi

  P2_START="$(printf '%s\n' "$PARTITION_TABLE" | awk -v p="${DISK}2" '$1==p {print $2; exit}')"
  P2_SIZE="$(printf '%s\n' "$PARTITION_TABLE" | awk -v p="${DISK}2" '$1==p {print $4; exit}')"
  case "$P2_START:$P2_SIZE" in *[!0-9:]*|:|*:) die "Cannot parse partition 2 layout.";; esac
  P2_END=$((P2_START + P2_SIZE - 1))
  START_SECTOR=$(( (P2_END + 2048) / 2048 * 2048 ))
  [ "$START_SECTOR" -lt "$DISK_SECTORS" ] || die "No unallocated space after partition 2."
  REMAINING=$((DISK_SECTORS - START_SECTOR))
  [ "$REMAINING" -ge 8192 ] || die "Remaining space is too small for Home."

  log "Creating partition 3 at sector $START_SECTOR to disk end."
  printf 'n\np\n3\n%s\n\nw\n' "$START_SECTOR" | fdisk "$DISK" >/dev/null
  command -v partprobe >/dev/null 2>&1 && partprobe "$DISK" 2>/dev/null || true
  sleep 2
  [ -b "$PART" ] || die "$PART did not appear after partition-table update."
  mkfs.ext4 -F -L "$LABEL" "$PART"
fi

[ -d "$MOUNTPOINT" ] || mkdir -p "$MOUNTPOINT"
if awk -v m="$MOUNTPOINT" '$2==m {found=1} END{exit found?0:1}' /proc/mounts; then
  CURRENT="$(awk -v m="$MOUNTPOINT" '$2==m {print $1; exit}' /proc/mounts)"
  [ "$CURRENT" = "$PART" ] || die "$MOUNTPOINT already mounted from $CURRENT."
fi

UUID="$(blkid -s UUID -o value "$PART" 2>/dev/null || true)"
[ -n "$UUID" ] || die "Cannot read UUID of $PART."

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
log "Boot and Root partitions were not formatted or resized."
