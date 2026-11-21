#!/bin/sh
# Smart-Net proxy stack installer for OpenWrt 25.12 / apk.
# Installs trusted-feed proxy cores, OpenClash (Mihomo manager), PassWall2, and its
# fw4/nftables dependencies. Does not enable services or alter
# routing, firewall, DNS, WAN/LAN, or wireless configuration.

set -eu

PATH="/usr/sbin:/usr/bin:/sbin:/bin"
export PATH

REPORT="${SMARTNET_REPORT_FILE:-/root/smartnet-bootstrap-report.txt}"
PASSWALL2_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall2.git"
PASSWALL_PACKAGES_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git"
PASSWALL2_SOURCE_DIR="/home/smartnet/sources/passwall2"
PASSWALL_PACKAGES_SOURCE_DIR="/home/smartnet/sources/passwall-packages"
OPENCLASH_PACKAGE="luci-app-openclash"
OPENCLASH_INSTALL_URL="https://raw.githubusercontent.com/vernesong/OpenClash/dev/install.sh"
OPENCLASH_RELEASE_BRANCH="master"

log() { printf '[06-proxy-stack] %s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }
package_installed() { apk info -e "$1" >/dev/null 2>&1; }
package_available() { apk search -x "$1" 2>/dev/null | grep -q .; }

install_core() {
    pkg="$1"
    if package_installed "$pkg"; then
        report "06-proxy-stack: installed: $pkg"
        log "$pkg is already installed"
        return 0
    fi
    if ! package_available "$pkg"; then
        report "06-proxy-stack: unavailable in configured trusted feeds: $pkg"
        log "$pkg is unavailable in configured feeds"
        return 1
    fi
    log "Installing $pkg"
    if apk add "$pkg" >/dev/null 2>&1 && package_installed "$pkg"; then
        report "06-proxy-stack: installation successful: $pkg"
        log "$pkg installed successfully"
        return 0
    fi
    report "06-proxy-stack: installation failed: $pkg"
    log "Installation failed for $pkg"
    return 1
}

discover_only() {
    pkg="$1"
    if package_installed "$pkg"; then
        report "06-proxy-stack: already installed (not modified): $pkg"
        log "$pkg is installed; no changes requested"
    elif package_available "$pkg"; then
        report "06-proxy-stack: available (not installed): $pkg"
        log "$pkg is available; left uninstalled"
    else
        report "06-proxy-stack: unavailable in configured feeds: $pkg"
        log "$pkg is unavailable in configured feeds"
    fi
}

install_openclash() {
    [ -r /etc/openwrt_release ] || {
        report "06-proxy-stack: OpenClash skipped; OpenWrt release metadata missing"
        return 1
    }
    . /etc/openwrt_release
    release="${DISTRIB_RELEASE:-unknown}"
    arch="${DISTRIB_ARCH:-unknown}"
    case "$release" in 25.12*) ;; *) report "06-proxy-stack: OpenClash skipped for unsupported release=$release"; return 1 ;; esac
    [ "$arch" = "i386_pentium4" ] || {
        report "06-proxy-stack: OpenClash skipped for unsupported APK architecture=$arch"
        return 1
    }
    command -v curl >/dev/null 2>&1 || return 1
    command -v sha256sum >/dev/null 2>&1 || return 1

    if package_installed "$OPENCLASH_PACKAGE"; then
        report "06-proxy-stack: OpenClash LuCI package already installed"
        log "OpenClash is already installed"
        return 0
    fi

    # Install the same official runtime prerequisites documented upstream,
    # but do not run the upstream bootstrap script: it may replace dnsmasq
    # and temporarily rewrite /etc/resolv.conf. Smart-Net owns network setup.
    deps="bash curl ca-bundle dnsmasq-full ip-full ruby ruby-yaml ruby-psych ruby-pstore unzip kmod-tun"
    for pkg in $deps; do
        if ! package_installed "$pkg"; then
            if ! package_available "$pkg"; then
                report "06-proxy-stack: required OpenClash dependency unavailable: $pkg"
                log "Missing OpenClash dependency in trusted feeds: $pkg"
                return 1
            fi
            if ! apk add "$pkg"; then
                report "06-proxy-stack: failed to install OpenClash dependency: $pkg"
                return 1
            fi
        fi
    done

    # Our OpenWrt 25.12 build uses Firewall4/nftables, not legacy iptables.
    for pkg in kmod-nft-tproxy luci-compat luci luci-base; do
        if ! package_installed "$pkg"; then
            if ! package_available "$pkg" || ! apk add "$pkg"; then
                report "06-proxy-stack: failed to install OpenClash dependency: $pkg"
                return 1
            fi
        fi
    done

    tmp="/tmp/smartnet-openclash-$$"
    mkdir -p "$tmp"
    trap 'rm -rf "$tmp"' 0 HUP INT TERM
    release_json="$tmp/release.json"

    log "Resolving official OpenClash APK release"
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 \
        "https://api.github.com/repos/vernesong/OpenClash/releases/latest" -o "$release_json"; then
        report "06-proxy-stack: OpenClash release API request failed"
        return 1
    fi

    # Extract only the APK asset URL, never the IPK package.
    download_url="$(jsonfilter -i "$release_json" -e '@.assets[*].browser_download_url' 2>/dev/null | grep '\\.apk$' | head -n1 || true)"
    [ -n "$download_url" ] || {
        report "06-proxy-stack: official OpenClash APK asset not found in latest release"
        return 1
    }
    if ! curl -fL --retry 3 --connect-timeout 15 --max-time 300 "$download_url" -o "$tmp/openclash.apk"; then
        report "06-proxy-stack: OpenClash APK download failed"
        return 1
    fi

    apk add --force-overwrite --clean-protected --allow-untrusted "$tmp/openclash.apk" || {
        report "06-proxy-stack: OpenClash APK installation failed"
        return 1
    }
    package_installed "$OPENCLASH_PACKAGE" || {
        report "06-proxy-stack: APK install returned but luci-app-openclash is not installed"
        return 1
    }

    report "06-proxy-stack: official OpenClash APK installed and verified"
    log "OpenClash installed; its proxy service remains disabled"
    rm -rf "$tmp"
    trap - 0 HUP INT TERM
    return 0
}

fetch_git_source() {
    repo="$1"
    dest="$2"
    label="$3"

    command -v git >/dev/null 2>&1 || {
        report "06-proxy-stack: $label source fetch skipped; git missing"
        log "$label source fetch skipped: git is not installed"
        return 1
    }
    mkdir -p "$(dirname "$dest")"

    if [ -d "$dest/.git" ]; then
        log "Updating official $label source in $dest"
        if git -C "$dest" pull --ff-only; then
            report "06-proxy-stack: official $label source updated: $dest"
            return 0
        fi
        report "06-proxy-stack: official $label source update failed; existing checkout retained: $dest"
        log "$label source update failed; preserving existing checkout"
        return 1
    fi

    if [ -e "$dest" ]; then
        report "06-proxy-stack: $label source destination exists but is not a Git checkout: $dest"
        log "$label source destination is occupied; refusing overwrite: $dest"
        return 1
    fi

    log "Cloning official $label source from GitHub"
    if git clone --depth 1 "$repo" "$dest"; then
        report "06-proxy-stack: official $label source cloned: $dest"
        return 0
    fi
    rm -rf "$dest"
    report "06-proxy-stack: official $label source clone failed"
    log "$label source clone failed"
    return 1
}

install_passwall2_apk() {
    [ -f /etc/openwrt_release ] || {
        report "06-proxy-stack: PassWall2 install aborted; /etc/openwrt_release missing"
        return 1
    }

    . /etc/openwrt_release
    release="${DISTRIB_RELEASE%.*}"
    arch="${DISTRIB_ARCH:-unknown}"

    # This module's tested package target is the Clientron x86 / Pentium 4 ABI.
    if [ "$release" != "25.12" ] || [ "$arch" != "i386_pentium4" ]; then
        report "06-proxy-stack: PassWall2 APK feed not configured for release=$release arch=$arch"
        log "PassWall2 install skipped: expected OpenWrt 25.12 / i386_pentium4, got $release / $arch"
        return 1
    fi

    command -v curl >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 || {
        report "06-proxy-stack: PassWall2 install skipped; curl or sha256sum missing"
        log "PassWall2 install requires curl and sha256sum"
        return 1
    }

    key_url="https://sourceforge.net/projects/openwrt-passwall-build/files/apk.pub/download"
    key_sha256="52802b143489214e13b78f96599a147a638205cc22d9dd6d71229504e38ddc00"
    key_path="/etc/apk/keys/passwall.pub"
    key_tmp="/tmp/passwall-apk-key.tmp"
    feeds="/etc/apk/repositories.d/customfeeds.list"
    base_url="https://sourceforge.net/projects/openwrt-passwall-build/files/releases/packages-$release/$arch"

    mkdir -p /etc/apk/keys /etc/apk/repositories.d
    log "Fetching PassWall repository signing key"
    if ! curl -fL --connect-timeout 20 --max-time 120 "$key_url" -o "$key_tmp"; then
        rm -f "$key_tmp"
        report "06-proxy-stack: PassWall signing key download failed"
        return 1
    fi
    actual_key_sha256="$(sha256sum "$key_tmp" | awk '{print $1}')"
    if [ "$actual_key_sha256" != "$key_sha256" ]; then
        rm -f "$key_tmp"
        report "06-proxy-stack: PassWall signing key checksum mismatch; key not installed"
        log "PassWall signing key checksum mismatch; refusing to trust repository"
        return 1
    fi

    if [ -e "$key_path" ]; then
        existing_key_sha256="$(sha256sum "$key_path" | awk '{print $1}')"
        if [ "$existing_key_sha256" != "$key_sha256" ]; then
            rm -f "$key_tmp"
            report "06-proxy-stack: existing PassWall key differs from pinned key; refusing overwrite"
            log "Existing PassWall key differs; refusing overwrite"
            return 1
        fi
        rm -f "$key_tmp"
    else
        if ! cp "$key_tmp" "$key_path"; then
            rm -f "$key_tmp"
            report "06-proxy-stack: unable to install PassWall signing key"
            return 1
        fi
        chmod 0644 "$key_path"
        rm -f "$key_tmp"
    fi

    touch "$feeds"
    for feed in passwall_packages passwall_luci passwall2; do
        feed_line="$base_url/$feed/packages.adb"
        if ! grep -Fqx "$feed_line" "$feeds"; then
            printf '%s\n' "$feed_line" >> "$feeds"
        fi
    done

    log "Refreshing APK indexes for signed PassWall repositories"
    if ! apk update; then
        report "06-proxy-stack: APK index refresh failed for PassWall repositories"
        log "PassWall APK index refresh failed; package installation skipped"
        return 1
    fi

    if ! package_available luci-app-passwall2; then
        report "06-proxy-stack: luci-app-passwall2 not found after signed feed refresh"
        log "PassWall2 package not found in the configured 25.12 / i386_pentium4 feeds"
        return 1
    fi

    log "Installing luci-app-passwall2 from signed APK repository"
    if ! apk add luci-app-passwall2; then
        report "06-proxy-stack: luci-app-passwall2 installation failed"
        log "PassWall2 APK installation failed; inspect apk dependency output"
        return 1
    fi
    if ! package_installed luci-app-passwall2; then
        report "06-proxy-stack: PassWall2 install command returned but package is not installed"
        log "PassWall2 package verification failed"
        return 1
    fi
    report "06-proxy-stack: luci-app-passwall2 installed and verified from signed APK feed"
    log "PassWall2 LuCI package installed and verified"

    # Keep the LuCI interface in English; do not install language packs.
    if package_installed luci-i18n-passwall2-fa; then
        log "Removing previously installed Persian PassWall2 translation"
        if apk del luci-i18n-passwall2-fa; then
            report "06-proxy-stack: Persian translation removed; English interface retained"
        else
            report "06-proxy-stack: failed to remove Persian translation"
            log "Could not remove Persian translation package"
        fi
    fi
    return 0
}

target="$(. /etc/openwrt_release 2>/dev/null; echo "${DISTRIB_TARGET:-unknown}")"
arch="$(uname -m 2>/dev/null || echo unknown)"
apk_arch="$(apk --print-arch 2>/dev/null || echo unknown)"
report "06-proxy-stack: target=$target arch=$arch apk_arch=$apk_arch"

# Install cores only from the router's currently configured trusted feeds.
install_core sing-box || true
install_core xray-core || true
# Tiny is an alternative sing-box build, not an additional independent core.
discover_only sing-box-tiny

# OpenClash is the dedicated Mihomo manager. Its installer handles the
# LuCI package and optional core download; do not install a competing binary.
install_openclash || true

install_passwall2_nft_dependencies() {
    # OpenWrt 25.12 uses fw4/nftables. These are the required kernel
    # components selected by the official PassWall2 fw4 build:
    # nft_socket, nft_tproxy and nft_nat.
    required_packages="kmod-nft-socket kmod-nft-tproxy kmod-nft-nat"
    missing_packages=""

    for pkg in $required_packages; do
        if ! package_installed "$pkg"; then
            if package_available "$pkg"; then
                missing_packages="$missing_packages $pkg"
            else
                report "06-proxy-stack: required nft dependency unavailable: $pkg"
                log "Required nft dependency is unavailable: $pkg"
                return 1
            fi
        fi
    done

    if [ -n "$missing_packages" ]; then
        log "Installing PassWall2 nftables kernel dependencies:$missing_packages"
        if ! apk add $missing_packages; then
            report "06-proxy-stack: failed to install nft dependencies:$missing_packages"
            log "Failed to install PassWall2 nftables dependencies"
            return 1
        fi
    fi

    # Ask the kernel to load modules immediately. Some modules may be
    # built into the kernel and therefore absent from lsmod; package presence
    # is checked independently below.
    if command -v modprobe >/dev/null 2>&1; then
        for module in nft_socket nft_tproxy nft_nat; do
            if modprobe "$module" >/dev/null 2>&1; then
                log "Kernel module available: $module"
            else
                log "Kernel module not dynamically loadable (may be built-in): $module"
            fi
        done
    fi

    missing_packages=""
    for pkg in $required_packages; do
        if ! package_installed "$pkg"; then
            missing_packages="$missing_packages $pkg"
        fi
    done
    if [ -n "$missing_packages" ]; then
        report "06-proxy-stack: nft dependencies remain missing:$missing_packages"
        log "PassWall2 nftables dependencies remain missing:$missing_packages"
        return 1
    fi

    if ! command -v nft >/dev/null 2>&1; then
        report "06-proxy-stack: nft command missing"
        log "nftables userspace command is missing"
        return 1
    fi
    if ! nft list tables >/dev/null 2>&1; then
        report "06-proxy-stack: nft command could not query current ruleset"
        log "nftables userspace query failed"
        return 1
    fi

    report "06-proxy-stack: required fw4 nft APK dependencies installed: $required_packages"
    log "PassWall2 nftables APK dependencies installed; kernel module load attempted"
    return 0
}

install_passwall2_optional_dependencies() {
    # Useful protocol/helper packages supported by the i386 target.
    # Install only when a trusted configured feed provides them.
    optional_packages="chinadns-ng dns2socks hysteria naiveproxy tcping"
    for pkg in $optional_packages; do
        if package_installed "$pkg"; then
            report "06-proxy-stack: optional dependency already installed: $pkg"
        elif package_available "$pkg"; then
            log "Installing optional PassWall2 helper: $pkg"
            if apk add "$pkg"; then
                report "06-proxy-stack: optional dependency installed: $pkg"
            else
                report "06-proxy-stack: optional dependency install failed: $pkg"
                log "Optional helper could not be installed: $pkg"
            fi
        else
            report "06-proxy-stack: optional dependency unavailable in trusted feeds: $pkg"
            log "Optional helper unavailable in configured feeds: $pkg"
        fi
    done

    # These plugins are optional; do not fail the whole stack if absent.
    optional_plugins="xray-plugin v2ray-plugin"
    for pkg in $optional_plugins; do
        if package_installed "$pkg"; then
            report "06-proxy-stack: optional plugin already installed: $pkg"
        elif package_available "$pkg"; then
            if apk add "$pkg"; then
                report "06-proxy-stack: optional plugin installed: $pkg"
            else
                report "06-proxy-stack: optional plugin installation failed: $pkg"
            fi
        else
            report "06-proxy-stack: optional plugin unavailable: $pkg"
        fi
    done
}

# PassWall2 is a LuCI management application, not a proxy core.
# For an existing or newly installed panel, complete the fw4/nftables
# prerequisites and optional i386 protocol helpers without enabling services.
if ! package_installed luci-app-passwall2; then
    discover_only luci-app-passwall2
    fetch_git_source "$PASSWALL2_REPO" "$PASSWALL2_SOURCE_DIR" "PassWall2" || true
    fetch_git_source "$PASSWALL_PACKAGES_REPO" "$PASSWALL_PACKAGES_SOURCE_DIR" "PassWall2 dependency" || true
    install_passwall2_apk || true
fi

if package_installed luci-app-passwall2; then
    install_passwall2_nft_dependencies || true
    install_passwall2_optional_dependencies
else
    report "06-proxy-stack: PassWall2 dependencies skipped because luci-app-passwall2 is not installed"
fi

if command -v sing-box >/dev/null 2>&1; then
    version="$(sing-box version 2>/dev/null | head -n 1 || true)"
    report "06-proxy-stack: sing-box executable: ${version:-version unavailable}"
    log "sing-box executable: ${version:-version unavailable}"
fi
if command -v xray >/dev/null 2>&1; then
    version="$(xray version 2>/dev/null | head -n 1 || true)"
    report "06-proxy-stack: Xray executable: ${version:-version unavailable}"
    log "Xray executable: ${version:-version unavailable}"
fi
if package_installed "$OPENCLASH_PACKAGE"; then
    report "06-proxy-stack: OpenClash LuCI package verified"
    log "OpenClash package verified; activate it manually after configuring a profile"
fi

report "06-proxy-stack: no proxy service enabled and no routing/firewall/network configuration changed"
log "Proxy stack module completed; proxy services remain disabled."
