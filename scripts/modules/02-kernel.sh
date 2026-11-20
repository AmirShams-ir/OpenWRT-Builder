#!/bin/sh
# Conservative runtime kernel tuning; BBR only when the kernel advertises it.
set -eu
PATH="/usr/sbin:/usr/bin:/sbin:/bin"; export PATH
log() { printf '[02-kernel] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"; }

CC="$(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true)"
CURRENT_CC="$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo unknown)"
CURRENT_QDISC="$(cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo unknown)"

if printf '%s' "$CC" | grep -qw bbr && [ -w /proc/sys/net/ipv4/tcp_congestion_control ]; then
  echo bbr > /proc/sys/net/ipv4/tcp_congestion_control
  if [ -w /proc/sys/net/core/default_qdisc ]; then
    echo fq > /proc/sys/net/core/default_qdisc 2>/dev/null || true
  fi
  report "02-kernel: BBR selected; congestion control was $CURRENT_CC; qdisc was $CURRENT_QDISC"
else
  report "02-kernel: BBR unavailable; preserving congestion control=$CURRENT_CC and qdisc=$CURRENT_QDISC; available=$CC"
fi

# Preserve existing TCP Fast Open policy; only ensure SYN cookies are enabled.
if [ -w /proc/sys/net/ipv4/tcp_syncookies ]; then
  echo 1 > /proc/sys/net/ipv4/tcp_syncookies
fi
CURRENT_TFO="$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo unavailable)"
report "02-kernel: TCP Fast Open left unchanged ($CURRENT_TFO)"

if command -v sysctl >/dev/null 2>&1; then
  mkdir -p /etc/sysctl.d
  cat > /etc/sysctl.d/99-smartnet.conf <<'EOF'
# Smart-Net conservative router tuning
net.ipv4.tcp_syncookies=1
EOF
  sysctl -p /etc/sysctl.d/99-smartnet.conf >/dev/null 2>&1 || true
  report "02-kernel: persisted tcp_syncookies only"
else
  report "02-kernel: sysctl unavailable; runtime settings only"
fi
log "Kernel tuning completed; unsupported BBR and existing TCP Fast Open policy preserved."
