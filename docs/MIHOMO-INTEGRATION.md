# Nikki + Mihomo + LuCI integration

## Selected architecture

Nikki is the dedicated Mihomo manager. PassWall2 remains independent for its
supported cores.

- Core package: `mihomo-meta` (provides Mihomo)
- Manager/service: `nikki`
- LuCI interface: `luci-app-nikki`
- Other independent cores: sing-box and Xray
- Other manager: PassWall2

Do not install MinimaxFlora's `luci-app-mihomo`; Nikki is the selected UI.

## Target

Clientron uses OpenWrt 25.12.6, x86/generic, APK architecture
`i386_pentium4`.

## Package build and delivery

The Nikki upstream repository is:

https://github.com/nikkinikki-org/OpenWrt-nikki

Its official GitHub Actions build matrix includes both
`i386_pentium4` and `openwrt-25.12`. However, its published Pages feed is
not accessible from the Clientron network in Iran, and its release assets do
not currently provide a matching i386 package archive.

Smart-Net therefore builds the three required packages from the official
Nikki source using the official OpenWrt SDK action in
`.github/workflows/build.yml`. The workflow uploads them in the same
30-day GitHub Actions artifact as the firmware. This is a CI build stage,
not an ImageBuilder package injection: ImageBuilder still builds only the OS
and base packages.

The runtime module `scripts/modules/09-mihomo-luci.sh` queries this
repository's GitHub Actions API, locates the latest successful artifact,
downloads it from GitHub, checks the package SHA256SUMS file, and installs
the three architecture-matched APK files.

## Runtime installation and safety

The module:
1. Requires OpenWrt 25.12 and `i386_pentium4`.
2. Downloads the matching Smart-Net artifact from GitHub Actions.
3. Verifies APK checksums before installation.
4. Installs `mihomo-meta`, `nikki`, and `luci-app-nikki`.
5. Lets APK resolve runtime dependencies from the configured official OpenWrt feeds.
6. Does not start/enable Nikki, reload Firewall4, or alter routing/DNS.

The upstream Nikki install script uses `apk add --allow-untrusted` for its
own feed. Smart-Net's artifact method does not pretend a SHA256 checksum is
a cryptographic signature; the checksum verifies consistency with the
artifact's manifest, while trust in the artifact is based on the HTTPS
GitHub Actions artifact delivery and repository workflow.

## Firewall and activation

The Nikki package registers a Firewall4 UCI include named
`firewall.nikki`. Its rules are gated by Nikki's own configuration. The
module does not change `nikki.config.enabled`, start the service, or reload
Firewall4. Review the include and back up configuration before enabling Nikki.

Test Nikki alone; do not simultaneously enable PassWall2 transparent proxying.

## First build and test

1. Run the `Build Smart-Net OpenWrt` workflow on the feature branch manually.
2. Confirm the SDK package-build step succeeds and the artifact contains the
   three APKs plus `SHA256SUMS`.
3. On Clientron, pull the feature branch and run:
   `sh scripts/modules/09-mihomo-luci.sh`.
4. Verify:
   `apk info -e mihomo-meta`,
   `apk info -e nikki`,
   `apk info -e luci-app-nikki`,
   `mihomo -v`, and `uci get nikki.config.enabled`.
5. Open LuCI and confirm the Nikki interface; keep the service disabled
   until its profile and firewall behavior are reviewed.

## Upstream sources

- https://github.com/nikkinikki-org/OpenWrt-nikki
- https://github.com/MetaCubeX/mihomo
- https://github.com/Openwrt-Passwall/openwrt-passwall2
