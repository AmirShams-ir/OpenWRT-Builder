# Clientron E832 Smart-Net network profile

Extracted from SmartNet-OpenWrt-Backup(1).tar, including UCI export and
network interface/routes snapshots.

## Hardware observed
- Model: Clientron E832
- CPU: Intel Atom N270, x86/generic, 32-bit
- Ethernet: eth0, MAC 00:e0:c5:44:97:4f; installed package inventory includes
  kmod-r8169 and r8169-firmware.
- Wi-Fi: Qualcomm Atheros PCI device at
  pci0000:00/0000:00:1e.0/0000:03:00.0; installed inventory includes
  kmod-ath9k, wpad-basic-mbedtls, iw and wireless-regdb.

## Interfaces
- WAN: eth0, static 192.168.1.2/24, gateway 192.168.1.1.
- DNS: 192.168.1.1, 1.1.1.1, 8.8.8.8, 9.9.9.9; peer DNS disabled.
- LAN: br-lan bridge on eth1? Backup explicitly shows br-lan device ports eth0 nowhere;
  original UCI creates bridge without explicit ports. Confirm physical LAN mapping on device.
- LAN IPv4: 192.168.12.1/24.
- DHCP: start offset 3, lease time 24h. The previous limit of 253 is adjusted to 250
  to keep the offered range away from the broadcast address.

## Wi-Fi
- SSID: Smart-Net, WPA2-PSK, channel 1, 20 MHz, enabled.
- WPA passphrase is injected from the GitHub Actions secret SMARTNET_WIFI_KEY
  and is never stored in this repository.

## Notes
The backup's UCI configuration included a full firewall LAN-to-WAN forward.
The backup also contains SSH host private keys and an account password hash;
these are deliberately not copied into this public build.
