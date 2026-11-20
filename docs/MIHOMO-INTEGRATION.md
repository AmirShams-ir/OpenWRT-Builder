# Nikki + Mihomo + LuCI integration

## Selected architecture

Nikki is the dedicated Mihomo manager. PassWall2 remains independent for its
supported cores.

- Core package: mihomo-meta (provides Mihomo)
- Manager/service: nikki
- LuCI interface: luci-app-nikki
- Other independent cores: sing-box and Xray
- Other manager: PassWall2

Do not install MinimaxFlora's luci-app-mihomo; Nikki is the selected UI.

## Target

Clientron uses OpenWrt 25.12.6, x86/generic, APK architecture
i386_pentium4.

## Package build and delivery

The upstream source is https://github.com/nikkinikki-org/OpenWrt-nikki.
Its official build matrix supports i386_pentium4 and openwrt-25.12.

Smart-Net builds mihomo-meta, nikki, and luci-app-nikki from that
source using the official OpenWrt SDK action in
.github/workflows/build.yml. The workflow publishes the resulting
nikki-i386_pentium4.tar.gz as a public GitHub Release asset under the
stable tag smartnet-nikki.

The runtime module downloads that public release asset over HTTPS. It does
not use the GitHub Actions artifact download API, which requires
authentication and returns HTTP 401 to unauthenticated clients. ImageBuilder
continues to build only the OS and base packages; Nikki installation remains
the responsibility of the runtime bootstrap module.

## Runtime installation and safety

The module:
1. Requires OpenWrt 25.12 and i386_pentium4.
2. Downloads the public smartnet-nikki release asset from GitHub.
3. Checks the APK SHA256SUMS manifest.
4. Installs mihomo-meta, nikki, and luci-app-nikki.
5. Lets APK resolve runtime dependencies from the configured OpenWrt feeds.
6. Does not start/enable Nikki, reload Firewall4, or alter routing/DNS.

SHA256 checksums detect accidental or in-transit modification but are not a
cryptographic publisher signature. The release asset is delivered by GitHub
over HTTPS.

## Firewall and activation

The Nikki package registers a Firewall4 UCI include named firewall.nikki.
Its rules are gated by Nikki's own configuration. The module does not change
nikki.config.enabled, start the service, or reload Firewall4. Review the
include and back up configuration before enabling Nikki.

Test Nikki alone; do not simultaneously enable PassWall2 transparent proxying.

## First build and test

1. Run the Build Smart-Net OpenWrt workflow manually on the feature branch.
2. Confirm the SDK package-build step succeeds and the workflow publishes the
   smartnet-nikki release with nikki-i386_pentium4.tar.gz.
3. On Clientron, pull the feature branch and run:
   sh scripts/modules/09-mihomo-luci.sh
4. Verify:
   apk info -e mihomo-meta,
   apk info -e nikki,
   apk info -e luci-app-nikki,
   mihomo -v, and uci get nikki.config.enabled.
5. Open LuCI and confirm the Nikki interface; keep the service disabled
   until its profile and firewall behavior are reviewed.

## Upstream sources

- https://github.com/nikkinikki-org/OpenWrt-nikki
- https://github.com/MetaCubeX/mihomo
- https://github.com/Openwrt-Passwall/openwrt-passwall2
