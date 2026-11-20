#!/usr/bin/env bash
# Nikki feed preflight. This script fetches and inventories official signed
# repository metadata only; it does not install or trust APK package payloads.
set -Eeuo pipefail
WORK="${1:?Usage: build-nikki-packages.sh WORK_DIR IMAGEBUILDER_DIR}"
BUILDER="${2:?Usage: build-nikki-packages.sh WORK_DIR IMAGEBUILDER_DIR}"
BRANCH="${NIKKI_BRANCH:-openwrt-25.12}"
ARCH="${NIKKI_ARCH:-i386_pentium4}"
BASE="${NIKKI_FEED_BASE:-https://nikkinikki.pages.dev}"
[[ -f "$BUILDER/Makefile" ]] || { echo "Invalid ImageBuilder" >&2; exit 1; }
[[ "$BRANCH:$ARCH" = "openwrt-25.12:i386_pentium4" ]] || { echo "Unsupported Nikki target" >&2; exit 1; }
bash "$(dirname "$0")/integrate-nikki.sh" "$BUILDER" "$WORK"
echo "Nikki upstream feed metadata downloaded."
echo "Package installation is deliberately disabled pending verification of the signed local APK repository workflow."
