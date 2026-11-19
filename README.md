# OpenWRT-Builder

A reproducible GitHub Actions build pipeline for a custom OpenWrt image for
the Smart-Net Clientron E832 router.

The repository currently focuses on the first milestone: a clean, verified
OpenWrt ImageBuilder build. A GUI and public multi-user build service are
intentionally out of scope until the firmware has been installed and tested
on the target hardware.

## Current build profile

| Setting | Value |
| --- | --- |
| OpenWrt | 25.12.6 |
| Target | \`x86/generic\` |
| Profile | \`generic\` |
| Image | BIOS / ext4 / combined |
| Boot partition | 100 MiB |
| Root partition | 5,120 MiB (5 GiB) |
| Additional packages | \`kmod-ath9k\`, \`wpad-basic-mbedtls\`, \`iw\` |

The generic x86 profile already supplies the Realtek Ethernet support used by
the device. The additional package list enables the Qualcomm Atheros PCI
wireless adapter and its userspace support.

## Build online

1. Open the repository's **Actions** tab.
2. Select **Build Smart-Net OpenWrt**.
3. Press **Run workflow** on the \`main\` branch.
4. Open the completed run and download the artifact named
   \`smartnet-openwrt-25.12.6-x86-generic\`.

A push to \`main\` that changes build configuration, files, or scripts also
starts a build automatically.

The artifact contains the compressed firmware image, package manifest,
build log, build information, and SHA256 checksum.

## Build locally

On a GNU/Linux x86_64 host (including Debian 13 or Ubuntu), install:

\`\`\`sh
sudo apt update
sudo apt install -y ca-certificates curl file gawk gzip make python3 tar xz-utils zstd
\`\`\`

Then run:

\`\`\`sh
git clone https://github.com/AmirShams-ir/OpenWRT-Builder.git
cd OpenWRT-Builder
bash scripts/build.sh
\`\`\`

The script verifies the official ImageBuilder SHA256 checksum and resets
\`PATH\` to a clean Linux path, avoiding the WindowsApps PATH issue seen under
WSL2.

Optional environment variables: \`OPENWRT_VERSION\`, \`OPENWRT_TARGET\`,
\`OPENWRT_SUBTARGET\`, \`OPENWRT_PROFILE\`, \`KERNEL_PARTSIZE_MIB\`,
\`ROOTFS_PARTSIZE_MIB\`, \`BUILD_ROOT\`, and \`OUTPUT_DIR\`.

## Partitioning: scope of this milestone

The ImageBuilder stage creates and verifies two fixed partitions:

1. Boot: 100 MiB
2. Root: 5 GiB

It does **not** create the Home partition yet. The remaining space depends on
the actual DOM capacity, so Home will be created by a separate disk-aware
installation step after the base image is successfully built and tested.
This avoids baking an assumed disk capacity into an image that may be written
to a slightly smaller DOM.

The verification script checks the MBR signature, partition count, types,
and exact Boot/Root sizes. The build succeeds only after these checks and the
gzip integrity test pass.

## Network configuration

The first image deliberately retains OpenWrt's stock first-boot network
configuration. This avoids replacing the default access path before the
existing Clientron configuration has been migrated safely. The known values
are documented in [docs/NETWORK-PLAN.md](docs/NETWORK-PLAN.md).

Never commit the WPA2 passphrase, private keys, SSH host keys, or backup
archives to this public repository.

## Repository layout

\`\`\`text
.github/workflows/build.yml   GitHub Actions workflow
config/packages.txt           Additional OpenWrt packages
docs/NETWORK-PLAN.md          Existing router network plan
files/                        Optional ImageBuilder filesystem overlay
scripts/build.sh              Download, verify, configure, and build
scripts/verify-image.py       Validate the generated MBR layout
\`\`\`

## References

- [OpenWrt 25.12.6 x86/generic downloads](https://downloads.openwrt.org/releases/25.12.6/targets/x86/generic/)
- [OpenWrt ImageBuilder documentation](https://openwrt.org/docs/guide-user/additional-software/imagebuilder)
- [OpenWrt x86 installation and partition layout](https://openwrt.org/docs/guide-user/installation/openwrt_x86)
