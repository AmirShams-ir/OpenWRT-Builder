#!/bin/sh
# Minimal web-hosting package probe; full PHP/database stack remains opt-in.
set -eu
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
if apk add nginx >/dev/null 2>&1; then
 report "08-webhosting: nginx available/installed; service not started"
else report "08-webhosting: nginx package unavailable"; fi
report "08-webhosting: PHP-FPM/database not installed by default; validate target and resources first"
echo '[08-webhosting] Web-hosting prerequisite check completed.'
