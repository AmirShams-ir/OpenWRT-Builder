#!/bin/sh
# Smart-Net runtime installer for Nikki + Mihomo + LuCI.
# Packages are built from the official Nikki source by this repository's CI.
# ImageBuilder remains responsible only for the OS and base packages.
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
need_cmd unzip
need_cmd sha256sum
need_cmd jsonfilter
need_cmd grep
need_cmd find

REPO_OWNER="AmirShams-ir"
REPO_NAME="OpenWRT-Builder"
ARTIFACT_NAME="smartnet-openwrt-25.12.6-x86-generic"
API_BASE="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME"
TMP_DIR="$(mktemp -d /tmp/nikki-install.XXXXXX)" || fail "cannot create temporary directory"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

# Resolve the latest successful workflow run from this repository's default branch.
log "Looking up the latest successful Smart-Net build on GitHub."
RUNS_JSON="$TMP_DIR/runs.json"
if ! curl -fsSL --retry 3 --connect-timeout 15 \
  "$API_BASE/actions/runs?branch=main&status=success&per_page=30" -o "$RUNS_JSON"; then
  fail "cannot query GitHub Actions runs"
fi

RUN_ID="$(jsonfilter -i "$RUNS_JSON" -e '@.workflow_runs[@.path=".github/workflows/build.yml" && @.conclusion="success"].id' 2>/dev/null | head -n1 || true)"
[ -n "$RUN_ID" ] || fail "no successful Smart-Net workflow run found on main"

ARTIFACTS_JSON="$TMP_DIR/artifacts.json"
if ! curl -fsSL --retry 3 --connect-timeout 15 \
  "$API_BASE/actions/runs/$RUN_ID/artifacts" -o "$ARTIFACTS_JSON"; then
  fail "cannot query build artifacts for run $RUN_ID"
fi

ARTIFACT_ID="$(jsonfilter -i "$ARTIFACTS_JSON" -e "@.artifacts[@.name=\"$ARTIFACT_NAME\" && @.expired=false].id" 2>/dev/null | head -n1 || true)"
[ -n "$ARTIFACT_ID" ] || fail "Nikki package artifact is missing or expired in run $RUN_ID"

ZIP="$TMP_DIR/nikki-packages.zip"
if ! curl -fL --retry 3 --connect-timeout 15 \
  "$API_BASE/actions/artifacts/$ARTIFACT_ID/zip" -o "$ZIP"; then
  fail "cannot download Nikki package artifact $ARTIFACT_ID"
fi

# Validate archive paths before extraction (reject traversal and unexpected paths).
if ! unzip -Z1 "$ZIP" > "$TMP_DIR/archive.list"; then
  fail "downloaded GitHub artifact is not a valid ZIP archive"
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TMP_DIR/archive.list"; then
  fail "artifact contains unsafe archive paths"
fi
mkdir "$TMP_DIR/unpacked"
if ! unzip -q "$ZIP" -d "$TMP_DIR/unpacked"; then
  fail "cannot extract Nikki package artifact"
fi

PKG_DIR="$TMP_DIR/unpacked/nikki/i386_pentium4"
[ -d "$PKG_DIR" ] || fail "package directory missing from artifact"
(
  cd "$PKG_DIR"
  sha256sum -c SHA256SUMS
) || fail "package checksum verification failed"

# Install only the three packages built for this exact OpenWrt architecture.
set --
for pkg in mihomo-meta nikki luci-app-nikki; do
  file="$(find "$PKG_DIR" -maxdepth 1 -type f -name "$pkg-*.apk" -print -quit)"
  [ -n "$file" ] || fail "required APK missing: $pkg"
  set -- "$@" "$file"
done

log "Refreshing official OpenWrt APK indexes."
if ! apk update; then fail "official OpenWrt APK index refresh failed"; fi

log "Installing Nikki packages built for OpenWrt 25.12 / i386_pentium4."
# The package payloads are from upstream Nikki source and checksum-verified
# against the artifact produced by this project's GitHub Actions workflow.
# APK still resolves and installs dependencies from the configured OpenWrt feeds.
if ! apk add --allow-untrusted "$@"; then
  fail "APK installation failed; inspect dependency and architecture errors"
fi

missing=""
for pkg in mihomo-meta nikki luci-app-nikki; do
  installed "$pkg" || missing="$missing $pkg"
done
[ -z "$missing" ] || fail "post-install verification failed; missing:$missing"

ENABLED="$(uci -q get nikki.config.enabled 2>/dev/null || echo 0)"
report "09-mihomo-luci: installed mihomo-meta nikki luci-app-nikki from GitHub Actions run $RUN_ID"
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
