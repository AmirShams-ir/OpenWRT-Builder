#!/usr/bin/env bash
set -Eeuo pipefail
BUILDER_DIR="${1:?Usage: integrate-nikki.sh IMAGEBUILDER_DIR WORK_DIR}"
WORK_DIR="${2:?Usage: integrate-nikki.sh IMAGEBUILDER_DIR WORK_DIR}"
BRANCH="${NIKKI_BRANCH:-openwrt-25.12}"
ARCH="${NIKKI_ARCH:-i386_pentium4}"
BASE="${NIKKI_FEED_BASE:-https://nikkinikki.pages.dev}"
[[ -f "$BUILDER_DIR/Makefile" && -d "$BUILDER_DIR/target" ]] || { echo "Invalid ImageBuilder" >&2; exit 1; }
[[ "$BRANCH:$ARCH" = "openwrt-25.12:i386_pentium4" ]] || { echo "Unsupported Nikki target: $BRANCH/$ARCH" >&2; exit 1; }
command -v curl >/dev/null
command -v python3 >/dev/null
FEED="$BASE/$BRANCH/$ARCH/nikki"
mkdir -p "$WORK_DIR/nikki-feed" "$WORK_DIR/nikki-apks"
curl -fL --retry 3 "$FEED/index.json" -o "$WORK_DIR/nikki-feed/index.json"
curl -fL --retry 3 "$FEED/packages.adb" -o "$WORK_DIR/nikki-apks/packages.adb"
curl -fL --retry 3 "$FEED/public-key.pem" -o "$WORK_DIR/nikki-feed/public-key.pem"
python3 - "$WORK_DIR/nikki-feed/index.json" "$FEED" "$WORK_DIR/nikki-apks" <<'PY'
import json, pathlib, subprocess, sys, urllib.parse
idx, base, out = sys.argv[1:]
data = json.loads(pathlib.Path(idx).read_text())
pkgs = data.get("packages", {})
for name in ("mihomo-meta", "nikki", "luci-app-nikki"):
    version = pkgs.get(name)
    if not version: raise SystemExit("Required Nikki package missing: " + name)
    filename = f"{name}-{version}.apk"
    subprocess.run(["curl", "-fL", "--retry", "3", base + "/" + urllib.parse.quote(filename),
                    "-o", str(pathlib.Path(out) / filename)], check=True)
PY
for f in "$WORK_DIR/nikki-apks"/mihomo-meta-*.apk "$WORK_DIR/nikki-apks"/nikki-*.apk "$WORK_DIR/nikki-apks"/luci-app-nikki-*.apk; do
  [[ -s "$f" ]] || { echo "Missing required package: $f" >&2; exit 1; }
done
(cd "$WORK_DIR/nikki-apks" && sha256sum *.apk > SHA256SUMS)
printf '%s\n' "$FEED" > "$WORK_DIR/nikki-feed-url.txt"
echo "Prepared official Nikki APKs: mihomo-meta, nikki, luci-app-nikki"
