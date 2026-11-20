# Nikki + Mihomo + LuCI integration

## Selected architecture

Nikki is the dedicated Mihomo manager. PassWall2 remains an independent manager
for its own supported cores.

- Core package: `mihomo-meta` (provides Mihomo)
- Manager/service: `nikki`
- LuCI interface: `luci-app-nikki`
- Other independent cores: sing-box and Xray
- Other manager: PassWall2

Do not install MinimaxFlora's `luci-app-mihomo`; it is not the selected UI.

## Pinned target

- OpenWrt 25.12.6
- Target x86/generic
- Package architecture i386_pentium4
- Nikki feed branch openwrt-25.12

Official feed:
https://nikkinikki.pages.dev/openwrt-25.12/i386_pentium4/nikki

## Package ownership

`mihomo-meta` provides Mihomo and owns the alternative mapping
`/usr/bin/mihomo -> /usr/libexec/mihomo`. `nikki` depends on Mihomo,
firewall4, ip-full, curl, yq and kernel modules. `luci-app-nikki` depends on
`nikki`.

The previous standalone Mihomo binary installer must not overwrite the package
managed binary. Nikki is the only manager for this instance of Mihomo.

## Firewall and activation safety

The upstream package adds a Firewall4 UCI include named `firewall.nikki`
through UCI defaults. Its script conditionally adds accept rules for the TUN
device only when Nikki is enabled and transparent proxying is enabled.

The upstream default sets `nikki.config.enabled=0`; therefore the service
does not start. The integration does not enable Nikki, start its service,
reload Firewall4, or alter WAN/LAN, DHCP, DNS, Wi-Fi or routing.

Note: package installation still registers the conditional firewall include.
This is an upstream package default, not runtime activation of transparent
proxying. Review it on first boot before enabling Nikki.

## Build method

ImageBuilder cannot compile Mihomo's Go sources. `scripts/integrate-nikki.sh`
downloads the official package set for the pinned release/architecture:
`mihomo-meta`, `nikki`, and `luci-app-nikki`. APK metadata and files are
required before firmware build proceeds. The public key is retained in the
work directory; unsigned installation is prohibited.

The workflow must verify package signatures and make the local APK repository
available to ImageBuilder. Fail the build if signature verification fails or
the exact package set is unavailable.

## Manual test after boot

1. Open LuCI and confirm the Nikki menu is present.
2. Confirm all three packages are installed.
3. Verify `uci get nikki.config.enabled` returns `0`.
4. Inspect `uci show firewall.nikki` and `fw4 print`.
5. Add/import a profile and validate it while service remains disabled.
6. Only after backup and review, enable Nikki manually and test one routing
   mode. Do not run Nikki and PassWall2 transparent-proxy modes simultaneously.

## Upstream

- https://github.com/nikkinikki-org/OpenWrt-nikki
- https://github.com/MetaCubeX/mihomo
- https://github.com/Openwrt-Passwall/openwrt-passwall2
