#!/bin/sh
# Install Nikki + Mihomo + LuCI at runtime, not in ImageBuilder.
# This follows the official Nikki APK installation method.
# The service remains disabled by upstream default (nikki.config.enabled=0).
set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
log() { printf '[09-mihomo-luci] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }
installed() { apk info -e "$1" >/dev/null 2>&1; }

[ -r /etc/openwrt_release ] || {
  report "09-mihomo-luci: skipped; /etc/openwrt_release missing"
  exit 0
}
. /etc/openwrt_release

case "${DISTRIB_RELEASE:-}" in
  *25.12*) NIKKI_BRANCH="openwrt-25.12" ;;
  *)
    report "09-mihomo-luci: unsupported OpenWrt release=${DISTRIB_RELEASE:-unknown}; no packages installed"
    log "Unsupported release; Nikki installation skipped."
    exit 0
    ;;
esac

ARCH="${DISTRIB_ARCH:-unknown}"
[ "$ARCH" = "i386_pentium4" ] || {
  report "09-mihomo-luci: unsupported package architecture=$ARCH; expected i386_pentium4"
  log "Unsupported architecture $ARCH; Nikki installation skipped."
  exit 0
}

[ -x /sbin/fw4 ] || {
  report "09-mihomo-luci: firewall4 not found; Nikki installation skipped"
  log "firewall4 is required."
  exit 0
}

FEED_URL="https://nikkinikki.pages.dev/$NIKKI_BRANCH/$ARCH/nikki"
REQUIRED="mihomo-meta nikki luci-app-nikki"

if installed mihomo-meta && installed nikki && installed luci-app-nikki; then
  log "Nikki package set is already installed; no reinstall needed."
else
  log "Refreshing APK indexes."
  if ! apk update; then
    report "09-mihomo-luci: apk update failed"
    log "APK index refresh failed; Nikki installation skipped."
    exit 0
  fi

  # This is the official upstream APK installation method. Nikki's own
  # install.sh uses --allow-untrusted with its packages.adb repository.
  # Do not replace it with a guessed signature-verification procedure.
  log "Installing Nikki, Mihomo and LuCI from the official Nikki feed."
  if ! apk add --allow-untrusted -X "$FEED_URL/packages.adb" $REQUIRED; then
    report "09-mihomo-luci: official Nikki APK installation failed"
    log "Nikki package installation failed; inspect APK output."
    exit 0
  fi
fi

missing=""
for pkg in $REQUIRED; do
  if ! installed "$pkg"; then missing="$missing $pkg"; fi
done
if [ -n "$missing" ]; then
  report "09-mihomo-luci: package verification failed; missing:$missing"
  log "Nikki package verification failed:$missing"
  exit 0
fi

ENABLED="$(uci -q get nikki.config.enabled 2>/dev/null || echo 0)"
report "09-mihomo-luci: installed $REQUIRED from $FEED_URL"
report "09-mihomo-luci: nikki.config.enabled=${ENABLED:-0}"

if [ "${ENABLED:-0}" = "0" ]; then
  log "Nikki installed successfully. Service remains disabled."
else
  report "09-mihomo-luci: WARNING service switch is not zero; no automatic change made"
  log "Nikki installed, but enabled switch is not zero. Review before proceeding."
fi

if uci -q get firewall.nikki >/dev/null 2>&1; then
  report "09-mihomo-luci: conditional firewall.nikki include registered; rules are gated by nikki.config.enabled"
else
  report "09-mihomo-luci: firewall.nikki include not detected"
fi

report "09-mihomo-luci: no Nikki service start/enable, no firewall reload, no routing or DNS changes performed"
