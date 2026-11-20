# Mihomo + LuCI integration

## Upstream selected

The UI/core package source is **MinimaxFlora/luci-app-mihomo**, a fork/port of
nikkinikki-org/OpenWrt-nikki. It contains two packages:

- `mihomo`: Core, procd init service, UCI defaults, ucode mixin and nftables
  transparent-proxy integration.
- `luci-app-mihomo`: LuCI interface, menu entry and RPC/ACL integration.

Upstream advertises OpenWrt 24.10/25.12 builds, including
`i386_pentium4`, and requires firewall4/kernel >= 5.13.

## Important architecture decision

Do not install the existing raw `/usr/bin/mihomo` binary and the package's
managed core in parallel. The upstream package owns the service lifecycle and
may install an alternative for `/usr/bin/mihomo`. The old standalone installer
must therefore be disabled when the managed package is selected.

Do not blindly enable transparent proxying during image construction. Keep the
initial state disabled until the profile, LAN access control and routing mode
have been reviewed on the target router. The upstream package has UCI defaults
and nftables integration, so its exact defaults and migration scripts must be
reviewed on every pinned upstream update.

## Build status / required pipeline

OpenWrt ImageBuilder installs binary packages; it cannot compile the upstream
Go package or LuCI feed from source. A matching OpenWrt 25.12 SDK build is
required first. The resulting APKs must match:

- OpenWrt release branch: 25.12
- Package architecture: `i386_pentium4`
- The exact target kernel ABI used by the generated firmware
- The exact package ABI/build metadata accepted by APK

The package set should include `mihomo` and `luci-app-mihomo`; include
translation packages only when deliberately selected. Prefer a signed local
APK repository and verify package metadata/signatures. Do not use
`--allow-untrusted` for production firmware.

## Firewall and network safety

The selected upstream core package can install nftables hooks and UCI defaults.
Before enabling it, inspect its init script, firewall include, UCI-defaults
and migration script. Keep the first install non-invasive:

1. Install UI/core packages.
2. Keep the service disabled.
3. Keep transparent proxy disabled.
4. Preserve current WAN/LAN/DHCP/DNS configuration.
5. Enable TProxy/TUN only after validating the selected mode and kernel modules.

## References

- https://github.com/MinimaxFlora/luci-app-mihomo
- https://github.com/nikkinikki-org/OpenWrt-nikki
- https://github.com/MetaCubeX/mihomo
