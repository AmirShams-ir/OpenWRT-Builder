#!/bin/sh
# Conservative runtime kernel tuning; BBR only when the kernel advertises it.
set -eu
PATH="/usr/sbin:/usr/bin:/sbin:/bin"; export PATH
log() { printf '[02-kernel] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }
CC="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true)"
if printf '%s' "$CC" | grep -qw bbr && [ -w /proc/sys/net/ipv4/tcp_congestion_control ]; then
 echo bbr > /proc/sys/net/ipv4/tcp_congestion_control
 if [ -w /proc/sys/net/core/default_qdisc ]; then echo fq > /proc/sys/net/core/default_qdisc 2>/dev/null || true; fi
 report "02-kernel: BBR selected; available=$CC"
else report "02-kernel: BBR unavailable; available congestion control: ${CC:-unknown}"; fi
[ ! -w /proc/sys/net/ipv4/tcp_syncookies ] || echo 1 > /proc/sys/net/ipv4/tcp_syncookies
[ ! -w /proc/sys/net/ipv4/tcp_fastopen ] || echo 3 > /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || true
if command -v sysctl >/dev/null 2>&1; then
 mkdir -p /etc/sysctl.d
 cat > /etc/sysctl.d/99-smartnet.conf <<'EOF'
# Smart-Net conservative router tuning
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_fastopen=3
EOF
 sysctl -p /etc/sysctl.d/99-smartnet.conf >/dev/null 2>&1 || true
 report "02-kernel: persisted conservative TCP settings"
else report "02-kernel: sysctl unavailable; runtime settings only"; fi
log "Kernel tuning completed."
