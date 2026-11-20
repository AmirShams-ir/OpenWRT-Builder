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

## Target

The Clientron image is OpenWrt 25.12.6, x86/generic, package architecture
`i386_pentium4`. Nikki's matching feed branch is `openwrt-25.12`.

Official feed:
https://nikkinikki.pages.dev/openwrt-25.12/i386_pentium4/nikki

## Installation ownership

ImageBuilder builds the OS and base packages only. Nikki is installed later by
`scripts/modules/09-mihomo-luci.sh`, invoked by `scripts/bootstrap.sh`.

The module:
1. Detects OpenWrt release and package architecture.
2. Uses only the matching official Nikki feed.
3. Installs `mihomo-meta`, `nikki`, and `luci-app-nikki`.
4. Verifies all three packages are installed.
5. Does not start/enable Nikki, reload Firewall4, or change routing/DNS.

Module 06 no longer installs a standalone Mihomo binary. The Nikki package owns
the Mihomo core path and service lifecycle.

## Upstream install behavior and trust note

The official Nikki `install.sh` uses:

```sh
apk add --allow-untrusted -X "$feed_url/packages.adb" mihomo-meta nikki luci-app-nikki
```

The runtime module follows this documented upstream method. Important: the
`--allow-untrusted` option means APK does not enforce normal repository
signature trust for those packages. This is upstream's published install
procedure; do not describe it as cryptographic signature verification.

## Firewall and activation safety

The Nikki package registers a Firewall4 UCI include named `firewall.nikki`
during package installation. The include script checks
`nikki.config.enabled` and only inserts TUN-device rules when Nikki is enabled,
not core-only, and proxy mode is enabled.

The upstream default config sets `nikki.config.enabled=0`. The module does not
change that setting, start/enable the service, or reload Firewall4. Review the
include on first boot before enabling Nikki.

## Test on Clientron

1. Boot the normal Smart-Net image and confirm WAN/LAN and LuCI work.
2. Run `sh /root/OpenWRT-Builder/scripts/bootstrap.sh` (or the installed
   project path) as root.
3. Check the bootstrap report for the three Nikki packages.
4. Verify `uci get nikki.config.enabled` returns `0`.
5. Open LuCI and confirm the Nikki menu and dashboard render.
6. Import a test profile. Keep Nikki disabled while checking the profile.
7. Inspect `uci show firewall.nikki` and `fw4 print`.
8. Back up the router configuration before manually enabling Nikki.
9. Test Nikki alone first; do not simultaneously enable PassWall2 transparent
   proxying.

## Upstream

- https://github.com/nikkinikki-org/OpenWrt-nikki
- https://github.com/MetaCubeX/mihomo
- https://github.com/Openwrt-Passwall/openwrt-passwall2
