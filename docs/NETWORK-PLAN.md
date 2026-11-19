# Clientron E832 network plan

This file records known settings from the existing Smart-Net router.
It is documentation only. The first CI image deliberately keeps OpenWrt's
stock first-boot network configuration until the wireless settings are
migrated safely.

## WAN

- Interface: \`eth0\`
- Protocol: static IPv4
- Address: \`192.168.1.2/24\`
- Gateway: \`192.168.1.1\`
- DNS: \`192.168.1.1\`, \`1.1.1.1\`, \`8.8.8.8\`, \`9.9.9.9\`
- Peer DNS: disabled

## LAN and DHCP

- Interface: \`lan\`
- Bridge: \`br-lan\`
- Address: \`192.168.12.1/24\`
- DHCP server: enabled
- Previously configured DHCP start offset: \`3\`

The existing configuration used a DHCP limit of 253. The exact resulting
lease range must be checked before migration; do not copy it blindly because
the broadcast address must not be offered to clients.

## Wireless

- SSID: \`Smart-Net\`
- Security: WPA2-PSK
- Driver: \`ath9k\`
- The WPA passphrase is intentionally not stored in this public repository.

The network profile will be migrated into the image after the wireless radio
configuration and secret-handling path have been verified.
