#!/bin/sh
# Smart-Net Installer 99
# Safely adds partition 3 in the unallocated tail of the known x86/MBR image.
# It never recreates the partition table and never formats an existing partition.
set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

DISK="${SMARTNET_DISK:-/dev/sda}"
MOUNTPOINT="/home/smartnet"
LABEL="SMARTNET_HOME"
LOCK="/var/lock/smartnet-installer99.lock"
CREATED=0

log() { printf '[Installer99] %s\n' "$*"; }
die() { printf '[Installer99] ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -b "$DISK" ] || die "Target disk does not exist: $DISK"
need awk
need basename
need blkid
need cat
need date
need dd
need grep
need ls
need mkdir
need mkfs.ext4
need mount
need partx
need readlink
need sfdisk
need sleep
need tr
need uci

DISK="$(readlink -f "$DISK")"
case "$DISK" in
  /dev/sd[a-z]|/dev/vd[a-z]) PART1="${DISK}1"; PART2="${DISK}2"; PART3="${DISK}3" ;;
  /dev/nvme[0-9]n[0-9]|/dev/mmcblk[0-9]) PART1="${DISK}p1"; PART2="${DISK}p2"; PART3="${DISK}p3" ;;
  *) die "Unsupported disk device: $DISK" ;;
esac

DISK_NAME="$(basename "$DISK")"
[ -r "/sys/class/block/$DISK_NAME/size" ] || die "Cannot read disk capacity from sysfs."
[ -r "/sys/class/block/$(basename "$PART1")/start" ] || die "Partition 1 sysfs data missing."
[ -r "/sys/class/block/$(basename "$PART1")/size" ] || die "Partition 1 size missing."
[ -r "/sys/class/block/$(basename "$PART2")/start" ] || die "Partition 2 sysfs data missing."
[ -r "/sys/class/block/$(basename "$PART2")/size" ] || die "Partition 2 size missing."

# Confirm this is the expected running two-partition BIOS image.
BOOT_SOURCE="$(awk '$2=="/boot" {print $1; exit}' /proc/mounts)"
[ "$BOOT_SOURCE" = "$PART1" ] || die "Expected /boot on $PART1; found ${BOOT_SOURCE:-none}."
CMDLINE="$(cat /proc/cmdline)"
ROOT_ARG="$(printf '%s\n' "$CMDLINE" | tr ' ' '\n' | awk 'index($0,"root=")==1 {sub(/^root=/,""); print; exit}')"
case "$ROOT_ARG" in
  "$PART2") ;;
  PARTUUID=*)
    EXPECTED="${ROOT_ARG#PARTUUID=}"
    ACTUAL="$(blkid -s PARTUUID -o value "$PART2" 2>/dev/null || true)"
    [ -n "$ACTUAL" ] && [ "$ACTUAL" = "$EXPECTED" ] || die "Kernel root PARTUUID does not match $PART2."
    ;;
  UUID=*)
    EXPECTED="${ROOT_ARG#UUID=}"
    ACTUAL="$(blkid -s UUID -o value "$PART2" 2>/dev/null || true)"
    [ -n "$ACTUAL" ] && [ "$ACTUAL" = "$EXPECTED" ] || die "Kernel root UUID does not match $PART2."
    ;;
  *) die "Cannot confirm that the running root filesystem is on $PART2 (kernel root argument: ${ROOT_ARG:-missing})." ;;
esac

mkdir -p /var/lock
if ! mkdir "$LOCK" 2>/dev/null; then die "Another Installer99 process appears to be running."; fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT HUP INT TERM

DISK_SECTORS="$(cat "/sys/class/block/$DISK_NAME/size")"
P1_START="$(cat "/sys/class/block/$(basename "$PART1")/start")"
P1_SIZE="$(cat "/sys/class/block/$(basename "$PART1")/size")"
P2_START="$(cat "/sys/class/block/$(basename "$PART2")/start")"
P2_SIZE="$(cat "/sys/class/block/$(basename "$PART2")/size")"
case "$DISK_SECTORS:$P1_START:$P1_SIZE:$P2_START:$P2_SIZE" in
  *[!0-9:]*|:*|*::*) die "Invalid disk or partition sector metadata." ;;
esac
[ "$DISK_SECTORS" -gt 0 ] || die "Invalid disk capacity."

TABLE="$(sfdisk --dump "$DISK" 2>/dev/null)" || die "Cannot read the partition table."
printf '%s\n' "$TABLE" | grep -q '^label: dos$' || die "Expected a DOS/MBR partition table."

# Require exactly partitions 1 and 2, plus optional partition 3; reject all
# other entries (including extended/logical partitions) rather than guessing.
COUNTS="$(printf '%s\n' "$TABLE" | awk -v p1="$PART1" -v p2="$PART2" -v p3="$PART3" '
  $1==p1 {a++} $1==p2 {b++} $1==p3 {c++}
  $1 ~ /^\/dev\// {n++}
  END {printf "%d:%d:%d:%d", a, b, c, n}
')"
[ "$COUNTS" = "1:1:0:2" ] || [ "$COUNTS" = "1:1:1:3" ] || die "Unexpected partition layout ($COUNTS); expected only partitions 1 and 2, with optional partition 3."

# Snapshot identity and both existing partition entries. Appending must not
# alter the MBR disk identifier, the bootable flag, or either existing entry.
protected_snapshot() {
  sfdisk --dump "$DISK" 2>/dev/null | awk -v p1="$PART1" -v p2="$PART2" '
    $1=="label:" || $1=="label-id:" || $1==p1 || $1==p2 {print}
  '
}
BEFORE_PROTECTED="$(protected_snapshot)"
[ -n "$BEFORE_PROTECTED" ] || die "Could not snapshot protected MBR entries."

if [ -b "$PART3" ]; then
  log "$PART3 already exists; it will not be formatted, resized, or deleted."
  TYPE="$(blkid -s TYPE -o value "$PART3" 2>/dev/null || true)"
  [ "$TYPE" = "ext4" ] || die "Existing $PART3 is not ext4; refusing to format it."
else
  # Calculate an aligned start sector (1 MiB boundary) after partition 2.
  P2_END=$((P2_START + P2_SIZE - 1))
  START=$(( (P2_END + 1 + 2047) / 2048 * 2048 ))
  [ "$START" -lt "$DISK_SECTORS" ] || die "No unallocated space remains after partition 2."
  REMAINING=$((DISK_SECTORS - START))
  [ "$REMAINING" -ge 8192 ] || die "Remaining free space is smaller than 4 MiB."

  # Keep a copy of the current MBR sector outside the target disk before change.
  BACKUP="/root/smartnet-mbr-${DISK_NAME}-$(date +%Y%m%d-%H%M%S).bin"
  dd if="$DISK" of="$BACKUP" bs=512 count=1 2>/dev/null || die "Could not back up the current MBR sector."
  [ -s "$BACKUP" ] || die "MBR backup is empty."
  log "Saved current MBR sector to $BACKUP"
  log "Appending only $PART3, starting at sector $START; existing partitions are not rewritten."

  # --append preserves the existing DOS disk label and entries. --no-reread
  # avoids asking the kernel to reread the busy whole disk; partx adds only #3.
  printf 'start=%s, size=+, type=83\n' "$START" | sfdisk --append --no-reread "$DISK" || die "sfdisk could not append partition 3."

  AFTER_PROTECTED="$(protected_snapshot)"
  [ "$AFTER_PROTECTED" = "$BEFORE_PROTECTED" ] || die "Protected MBR data changed unexpectedly; stopping before formatting. MBR backup: $BACKUP"

  partx --add --nr 3 "$DISK" || die "Partition table was written, but the kernel could not register partition 3. Do not rerun blindly; inspect with sfdisk --dump and partx."
  i=0
  while [ "$i" -lt 10 ] && [ ! -b "$PART3" ]; do sleep 1; i=$((i + 1)); done
  [ -b "$PART3" ] || die "$PART3 did not appear after partx. MBR backup: $BACKUP"

  CREATED=1
  mkfs.ext4 -F -L "$LABEL" "$PART3" || die "Formatting $PART3 failed. Partition exists; it will not be auto-formatted on a later run."
fi

# Verify the protected entries one more time before mounting.
AFTER_PROTECTED="$(protected_snapshot)"
[ "$AFTER_PROTECTED" = "$BEFORE_PROTECTED" ] || die "Existing MBR entries no longer match their pre-install values."

mkdir -p "$MOUNTPOINT"
if awk -v m="$MOUNTPOINT" '$2==m {found=1} END {exit found?0:1}' /proc/mounts; then
  CURRENT="$(awk -v m="$MOUNTPOINT" '$2==m {print $1; exit}' /proc/mounts)"
  [ "$CURRENT" = "$PART3" ] || die "$MOUNTPOINT is already mounted from $CURRENT; refusing to change it."
else
  if [ -n "$(ls -A "$MOUNTPOINT" 2>/dev/null || true)" ]; then
    die "$MOUNTPOINT contains files and is not mounted; refusing to hide them."
  fi
fi

UUID="$(blkid -s UUID -o value "$PART3" 2>/dev/null || true)"
[ -n "$UUID" ] || die "Could not read UUID of $PART3."

# Store the persistent mount. Do not restart fstab (which may disturb other
# mounts); mount this one filesystem directly for the current session.
uci -q delete fstab.smartnet_home 2>/dev/null || true
uci set fstab.smartnet_home='mount'
uci set fstab.smartnet_home.target="$MOUNTPOINT"
uci set fstab.smartnet_home.uuid="$UUID"
uci set fstab.smartnet_home.fstype='ext4'
uci set fstab.smartnet_home.options='rw,noatime'
uci set fstab.smartnet_home.enabled='1'
uci commit fstab
/etc/init.d/fstab enable

if ! awk -v m="$MOUNTPOINT" '$2==m {found=1} END {exit found?0:1}' /proc/mounts; then
  mount -t ext4 -o rw,noatime "$PART3" "$MOUNTPOINT" || die "Could not mount $PART3 at $MOUNTPOINT. Persistent fstab entry has been saved."
fi
awk -v m="$MOUNTPOINT" '$2==m {found=1} END {exit found?0:1}' /proc/mounts || die "Home mount verification failed."

log "Success: $PART3 is mounted at $MOUNTPOINT (UUID=$UUID)."
log "Partitions 1 and 2 and their MBR entries were preserved."
[ "$CREATED" -eq 1 ] && log "New filesystem created on $PART3." || log "Existing ext4 data on $PART3 was preserved."
