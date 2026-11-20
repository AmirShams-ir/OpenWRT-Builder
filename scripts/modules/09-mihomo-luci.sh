#!/bin/sh
# Smart-Net runtime installer for Nikki + Mihomo + LuCI.
# Packages are built from the official Nikki source by this repository's CI
# and downloaded as public GitHub Release assets (not Actions artifacts).
set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
log() { printf '[09-mihomo-luci] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }
installed() { apk info -e "$1" >/dev/null 2>&1; }
fail() {
  report "09-mihomo-luci: ERROR: $*"
  log "ERROR: $*"
  exit 0
}
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

[ -r /etc/openwrt_release ] || {
  report "09-mihomo-luci: skipped; /etc/openwrt_release missing"
  exit 0
}
. /etc/openwrt_release

case "${DISTRIB_RELEASE:-}" in
  *25.12*) ;;
  *)
    report "09-mihomo-luci: unsupported OpenWrt release=${DISTRIB_RELEASE:-unknown}"
    log "Unsupported OpenWrt release; installation skipped."
    exit 0
    ;;
esac

ARCH="${DISTRIB_ARCH:-unknown}"
[ "$ARCH" = "i386_pentium4" ] || {
  report "09-mihomo-luci: unsupported architecture=$ARCH; expected i386_pentium4"
  log "Unsupported package architecture; installation skipped."
  exit 0
}

[ -x /sbin/fw4 ] || fail "firewall4 is required"
need_cmd apk
need_cmd curl
need_cmd tar
need_cmd sha256sum
need_cmd jsonfilter
need_cmd grep
need_cmd find

REPO_OWNER="AmirShams-ir"
REPO_NAME="OpenWRT-Builder"
RELEASE_TAG="smartnet-nikki"
ARCHIVE_NAME="nikki-i386_pentium4.tar.gz"
API_BASE="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME"
TMP_DIR="$(mktemp -d /tmp/nikki-install.XXXXXX)" || fail "cannot create temporary directory"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

log "Looking up public Nikki package release on GitHub."
RELEASE_JSON="$TMP_DIR/release.json"
if ! curl -fsSL --retry 3 --connect-timeout 15 \
  "$API_BASE/releases/tags/$RELEASE_TAG" -o "$RELEASE_JSON"; then
  fail "cannot find public GitHub release '$RELEASE_TAG'; run the Smart-Net workflow first"
fi

DOWNLOAD_URL="$(jsonfilter -i "$RELEASE_JSON" -e "@.assets[@.name=\"$ARCHIVE_NAME\"].browser_download_url" 2>/dev/null | head -n1 || true)"
[ -n "$DOWNLOAD_URL" ] || fail "release asset $ARCHIVE_NAME is missing"

ARCHIVE="$TMP_DIR/$ARCHIVE_NAME"
if ! curl -fL --retry 3 --connect-timeout 15 "$DOWNLOAD_URL" -o "$ARCHIVE"; then
  fail "cannot download public GitHub release asset"
fi

# Reject absolute paths and parent traversal before extraction.
if ! tar -tzf "$ARCHIVE" > "$TMP_DIR/archive.list"; then
  fail "downloaded release asset is not a valid tar.gz archive"
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TMP_DIR/archive.list"; then
  fail "release archive contains unsafe paths"
fi

mkdir "$TMP_DIR/unpacked"
if ! tar -xzf "$ARCHIVE" -C "$TMP_DIR/unpacked"; then
  fail "cannot extract Nikki package archive"
fi
PKG_DIR="$TMP_DIR/unpacked"
(
  cd "$PKG_DIR"
  sha256sum -c SHA256SUMS
) || fail "package checksum verification failed"

set --
for pkg in mihomo-meta nikki luci-app-nikki; do
  file="$(find "$PKG_DIR" -maxdepth 1 -type f -name "$pkg-*.apk" -print -quit)"
  [ -n "$file" ] || fail "required APK missing: $pkg"
  set -- "$@" "$file"
done

log "Refreshing official OpenWrt APK indexes."
if ! apk update; then fail "official OpenWrt APK index refresh failed"; fi

log "Installing Nikki packages built for OpenWrt 25.12 / i386_pentium4."
# SHA256SUMS detects accidental or in-transit modification; it is not a
# cryptographic publisher signature. The release is served by GitHub HTTPS.
if ! apk add --allow-untrusted "$@"; then
  fail "APK installation failed; inspect dependency and architecture errors"
fi

missing=""
for pkg in mihomo-meta nikki luci-app-nikki; do
  installed "$pkg" || missing="$missing $pkg"
done
[ -z "$missing" ] || fail "post-install verification failed; missing:$missing"

ENABLED="$(uci -q get nikki.config.enabled 2>/dev/null || echo 0)"
report "09-mihomo-luci: installed mihomo-meta nikki luci-app-nikki from GitHub release $RELEASE_TAG"
report "09-mihomo-luci: package architecture=$ARCH; nikki.config.enabled=${ENABLED:-0}"

if [ "${ENABLED:-0}" = "0" ]; then
  log "Nikki packages installed. Nikki remains disabled."
else
  report "09-mihomo-luci: WARNING nikki.config.enabled is not zero; no automatic change made"
  log "Packages installed; inspect existing Nikki enable setting before use."
fi

if uci -q get firewall.nikki >/dev/null 2>&1; then
  report "09-mihomo-luci: firewall.nikki include exists; upstream rules remain gated by Nikki settings"
fi

report "09-mihomo-luci: no service start/enable, firewall reload, routing or DNS changes performed"
log "Installation complete; Nikki service state was not changed."
