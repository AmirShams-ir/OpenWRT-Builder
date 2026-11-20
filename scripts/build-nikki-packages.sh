#!/usr/bin/env bash
# Prepare Nikki's signed APK repository for OpenWrt ImageBuilder.
# Package artifacts are fetched by integrate-nikki.sh. The official repository
# index is retained and passed through unchanged; apk-tools verifies signatures.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK="${1:?Usage: build-nikki-packages.sh WORK_DIR}"
BUILDER="${2:?Usage: build-nikki-packages.sh WORK_DIR IMAGEBUILDER_DIR}"
NIKKI_MODE="${SMARTNET_NIKKI:-1}"
[[ "$NIKKI_MODE" = "1" ]] || { echo "Nikki integration disabled"; exit 0; }
bash "$ROOT/scripts/integrate-nikki.sh" "$BUILDER" "$WORK"
APK_DIR="$WORK/nikki-apks"
FEED="$WORK/nikki-feed-url.txt"
[[ -s "$APK_DIR/packages.adb" && -s "$WORK/nikki-feed/public-key.pem" ]] || {
  echo "Nikki signed package repository metadata missing" >&2; exit 1;
}
# Do not use apk add --allow-untrusted. The package database is signed by the
# upstream feed key; signature verification is delegated to the OpenWrt APK
# tooling at package installation time.
printf '%s\n' "Nikki packages prepared from $(cat "$FEED")"
