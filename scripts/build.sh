#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.6}"
OPENWRT_TARGET="${OPENWRT_TARGET:-x86}"
OPENWRT_SUBTARGET="${OPENWRT_SUBTARGET:-generic}"
OPENWRT_PROFILE="${OPENWRT_PROFILE:-generic}"
KERNEL_PARTSIZE_MIB="${KERNEL_PARTSIZE_MIB:-100}"
ROOTFS_PARTSIZE_MIB="${ROOTFS_PARTSIZE_MIB:-5120}"
BUILD_ROOT="${BUILD_ROOT:-${RUNNER_TEMP:-$ROOT_DIR/.build}}"
CACHE_DIR="${CACHE_DIR:-$BUILD_ROOT/cache}"
WORK_DIR="${WORK_DIR:-$BUILD_ROOT/work}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/output}"
FILES_DIR="${FILES_DIR:-$ROOT_DIR/files}"
CLEAN_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export PATH="$CLEAN_PATH"

log() { printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

for command in curl tar zstd sha256sum make python3 gzip grep awk sed tee; do
  command -v "$command" >/dev/null 2>&1 || die "Required command not found: $command"
done

[[ "$KERNEL_PARTSIZE_MIB" =~ ^[1-9][0-9]*$ ]] || die "Invalid KERNEL_PARTSIZE_MIB"
[[ "$ROOTFS_PARTSIZE_MIB" =~ ^[1-9][0-9]*$ ]] || die "Invalid ROOTFS_PARTSIZE_MIB"

BUILDER_NAME="openwrt-imagebuilder-${OPENWRT_VERSION}-${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}.Linux-x86_64.tar.zst"
BASE_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${OPENWRT_TARGET}/${OPENWRT_SUBTARGET}"
mkdir -p "$CACHE_DIR" "$WORK_DIR/tmp" "$OUTPUT_DIR"
find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type f -delete
: > "$OUTPUT_DIR/build.log"
exec > >(tee -a "$OUTPUT_DIR/build.log") 2>&1

log "OpenWrt ${OPENWRT_VERSION} / ${OPENWRT_TARGET}/${OPENWRT_SUBTARGET}"
log "Boot: ${KERNEL_PARTSIZE_MIB} MiB; Root: ${ROOTFS_PARTSIZE_MIB} MiB"

ARCHIVE_PATH="$CACHE_DIR/$BUILDER_NAME"
curl --fail --location --retry 3 --retry-delay 2 \
  --output "$ARCHIVE_PATH" "${BASE_URL}/${BUILDER_NAME}"
curl --fail --location --retry 3 --retry-delay 2 \
  --output "$CACHE_DIR/sha256sums" "${BASE_URL}/sha256sums"

awk -v filename="$BUILDER_NAME" '
    NF >= 2 {
      listed_name = $2
      sub(/^\\*/, "", listed_name)
      if (listed_name == filename) {
        print $1 "  " filename
        found = 1
        exit
      }
    }
    END {
      if (!found) exit 1
    }
  ' "$CACHE_DIR/sha256sums" > "$CACHE_DIR/builder.sha256"
[[ -s "$CACHE_DIR/builder.sha256" ]] || die "Builder archive missing from official checksum list."
(cd "$CACHE_DIR" && sha256sum --check --strict builder.sha256)

BUILDER_DIR="$WORK_DIR/openwrt-imagebuilder-${OPENWRT_VERSION}-${OPENWRT_TARGET}-${OPENWRT_SUBTARGET}.Linux-x86_64"
if [[ ! -d "$BUILDER_DIR" ]]; then
  tar --zstd -xf "$ARCHIVE_PATH" -C "$WORK_DIR"
fi
[[ -f "$BUILDER_DIR/Makefile" && -f "$BUILDER_DIR/.config" ]] || die "Invalid ImageBuilder archive."

CONFIG_FILE="$BUILDER_DIR/.config"
set_config_value() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$CONFIG_FILE"; then
    sed -i "s|^${key}=.*$|${key}=${value}|" "$CONFIG_FILE"
  elif grep -q "^# ${key} is not set$" "$CONFIG_FILE"; then
    sed -i "s|^# ${key} is not set$|${key}=${value}|" "$CONFIG_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$CONFIG_FILE"
  fi
}
unset_config_value() {
  local key="$1"
  if grep -q "^${key}=" "$CONFIG_FILE"; then
    sed -i "s|^${key}=.*$|# ${key} is not set|" "$CONFIG_FILE"
  elif ! grep -q "^# ${key} is not set$" "$CONFIG_FILE"; then
    printf '# %s is not set\n' "$key" >> "$CONFIG_FILE"
  fi
}

set_config_value CONFIG_TARGET_ROOTFS_EXT4FS y
unset_config_value CONFIG_TARGET_ROOTFS_SQUASHFS
set_config_value CONFIG_TARGET_KERNEL_PARTSIZE "$KERNEL_PARTSIZE_MIB"
set_config_value CONFIG_TARGET_ROOTFS_PARTSIZE "$ROOTFS_PARTSIZE_MIB"

PACKAGES_FILE="$ROOT_DIR/config/packages.txt"
[[ -f "$PACKAGES_FILE" ]] || die "Missing config/packages.txt"
PACKAGES="$(grep -Ev '^[[:space:]]*(#|$)' "$PACKAGES_FILE" | xargs || true)"
[[ -n "$PACKAGES" ]] || die "Package list is empty."

FILES_ARGS=()
if [[ -d "$FILES_DIR" ]] && find "$FILES_DIR" -type f ! -name '.gitkeep' -print -quit | grep -q .; then
  FILES_ARGS+=("FILES=$FILES_DIR")
  log "Using filesystem overlay: $FILES_DIR"
else
  log "No filesystem overlay: keeping stock first-boot network defaults"
fi

log "Generating package manifest"
(
  cd "$BUILDER_DIR"
  TMPDIR="$WORK_DIR/tmp" make manifest PROFILE="$OPENWRT_PROFILE" PACKAGES="$PACKAGES"
) > "$OUTPUT_DIR/manifest.txt"

log "Running ImageBuilder"
BUILD_ARGS=(
  image
  "PROFILE=$OPENWRT_PROFILE"
  "PACKAGES=$PACKAGES"
  "BIN_DIR=$OUTPUT_DIR"
  "CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE_MIB"
  "CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE_MIB"
)
BUILD_ARGS+=("${FILES_ARGS[@]}")

(
  cd "$BUILDER_DIR"
  PATH="$CLEAN_PATH" TMPDIR="$WORK_DIR/tmp" make "${BUILD_ARGS[@]}" V=s
)

mapfile -t IMAGES < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name '*ext4-combined.img.gz' ! -name '*efi*' -print)
[[ "${#IMAGES[@]}" -eq 1 ]] || die "Expected one BIOS ext4 combined image; found ${#IMAGES[@]}."
IMAGE_PATH="${IMAGES[0]}"

gzip --test "$IMAGE_PATH"
python3 "$ROOT_DIR/scripts/verify-image.py" "$IMAGE_PATH" \
  --kernel-mib "$KERNEL_PARTSIZE_MIB" --root-mib "$ROOTFS_PARTSIZE_MIB"

sha256sum "$IMAGE_PATH" > "$OUTPUT_DIR/sha256sums.txt"
cat > "$OUTPUT_DIR/build-info.txt" <<EOF
Smart-Net OpenWrt Build
OpenWrt version: ${OPENWRT_VERSION}
Target: ${OPENWRT_TARGET}/${OPENWRT_SUBTARGET}
Profile: ${OPENWRT_PROFILE}
Filesystem: ext4
Boot partition: ${KERNEL_PARTSIZE_MIB} MiB
Root partition: ${ROOTFS_PARTSIZE_MIB} MiB
Image: $(basename "$IMAGE_PATH")
Home partition: deferred to a disk-size-aware installation step.
EOF

log "Build completed: $IMAGE_PATH"
log "SHA256: $(awk '{print $1}' "$OUTPUT_DIR/sha256sums.txt")"
