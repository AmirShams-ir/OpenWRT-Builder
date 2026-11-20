#!/usr/bin/env bash
# Integrate the upstream luci-app-mihomo packages into the OpenWrt ImageBuilder.
# The upstream "mihomo" package owns the core binary and procd/firewall setup.
# Therefore the legacy standalone binary installer is disabled when this mode
# is selected. No feed is installed on the router at runtime.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILDER_DIR="${1:?Usage: integrate-mihomo.sh IMAGEBUILDER_DIR WORK_DIR}"
WORK_DIR="${2:?Usage: integrate-mihomo.sh IMAGEBUILDER_DIR WORK_DIR}"
FEED_REPO="https://github.com/MinimaxFlora/luci-app-mihomo.git"
FEED_REF="${MIHOMO_FEED_REF:-master}"
FEED_DIR="$WORK_DIR/feeds/mihomo"

[[ -f "$BUILDER_DIR/Makefile" && -d "$BUILDER_DIR/target" ]] || {
  echo "ERROR: invalid ImageBuilder directory: $BUILDER_DIR" >&2
  exit 1
}

mkdir -p "$(dirname "$FEED_DIR")"
if [[ -d "$FEED_DIR/.git" ]]; then
  git -C "$FEED_DIR" fetch --depth 1 origin "$FEED_REF"
  git -C "$FEED_DIR" checkout --detach FETCH_HEAD
elif [[ -e "$FEED_DIR" ]]; then
  echo "ERROR: feed path exists but is not a Git checkout: $FEED_DIR" >&2
  exit 1
else
  git clone --depth 1 --branch "$FEED_REF" "$FEED_REPO" "$FEED_DIR"
fi

# Verify the expected upstream package sources before wiring them into the build.
for file in   "$FEED_DIR/mihomo/Makefile"   "$FEED_DIR/luci-app-mihomo/Makefile"   "$FEED_DIR/mihomo/files/mihomo.init"   "$FEED_DIR/luci-app-mihomo/root/usr/share/luci/menu.d/luci-app-mihomo.json"; do
  [[ -s "$file" ]] || { echo "ERROR: upstream feed is incomplete: $file" >&2; exit 1; }
done

# ImageBuilder has no source-package build environment. Build the feed packages
# with the matching OpenWrt SDK (SDK_URL may be supplied by the caller), then
# copy only architecture/release-matching APKs into a local APK repository.
# The workflow invokes this script only after the SDK artifact has been built.
SDK_PACKAGES_DIR="${MIHOMO_SDK_PACKAGES_DIR:-}"
[[ -n "$SDK_PACKAGES_DIR" && -d "$SDK_PACKAGES_DIR" ]] || {
  echo "ERROR: MIHOMO_SDK_PACKAGES_DIR must point to the completed 25.12/i386_pentium4 SDK package directory." >&2
  exit 1
}
PKG_DIR="$(find "$SDK_PACKAGES_DIR" -maxdepth 2 -type f -name 'mihomo-*.apk' -printf '%h\n' | head -n1)"
[[ -n "$PKG_DIR" ]] || { echo "ERROR: no Mihomo APKs found in $SDK_PACKAGES_DIR" >&2; exit 1; }
for package in mihomo luci-app-mihomo; do
  find "$PKG_DIR" -maxdepth 1 -type f -name "$package-*.apk" -print -quit | grep -q . || {
    echo "ERROR: missing package $package in $PKG_DIR" >&2; exit 1;
  }
done
mkdir -p "$WORK_DIR/mihomo-apks"
cp -f "$PKG_DIR"/*.apk "$WORK_DIR/mihomo-apks/"
printf '%s\n' "$FEED_DIR" > "$WORK_DIR/mihomo-feed-source.txt"
printf '%s\n' "$WORK_DIR/mihomo-apks" > "$WORK_DIR/mihomo-apk-dir.txt"
echo "Mihomo feed source and signed/matching APK set prepared."
