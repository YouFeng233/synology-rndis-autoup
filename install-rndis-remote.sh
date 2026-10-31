#!/bin/sh
set -eu
fail() { echo "ERROR: $*" >&2; exit 1; }
cpu=$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -n 1)
platform=$(sed -n 's/^platform_name="\(.*\)"/\1/p' /etc/synoinfo.conf)
. /etc.defaults/VERSION
echo "CPU: $cpu"
echo "Platform: $platform; DSM: $productversion; kernel: $(uname -r)"
echo "$cpu" | grep -q 'AMD Ryzen Embedded V1500B' || fail "CPU must be AMD Ryzen Embedded V1500B"
[ "$platform" = v1000 ] || fail "Platform must be v1000 (not v1000nk)"
[ "$(uname -m)" = x86_64 ] || fail "Architecture must be x86_64"
[ "$(uname -r)" = 4.4.302+ ] || fail "Kernel must be 4.4.302+"
[ "$majorversion.$minorversion" = 7.4 ] || fail "Only DSM 7.4.x has been validated"
if [ "$(id -u)" != 0 ]; then exec sudo /bin/sh "$0"; fi
command -v curl >/dev/null || fail "curl missing"
command -v sha256sum >/dev/null || fail "sha256sum missing"
[ -x /bin/udevadm ] || fail "udevadm missing"
[ -x /sbin/ip ] || fail "ip missing"
stage=$(mktemp -d /tmp/rndis-setup.XXXXXX)
trap 'rm -rf "$stage"' EXIT
curl -fSL --connect-timeout 15 --max-time 120 -o "$stage/rndis_host.ko" 'https://raw.githubusercontent.com/robertklep/dsm7-usb-serial-drivers/b2f5f9be176c97f27fd808aeb2cbbeff56ade1db/modules/v1000/dsm-7.4/rndis_host.ko'
curl -fSL --connect-timeout 15 --max-time 180 -o "$stage/modules.tgz" 'https://github.com/AuxXxilium/arc-modules/releases/download/26.10.19/v1000-7.4-4.4.302.tgz'
tar -xOf "$stage/modules.tgz" ./mii.ko > "$stage/mii.ko"
tar -xOf "$stage/modules.tgz" ./cdc_ether.ko > "$stage/cdc_ether.ko"
check() { echo "$2  $1" | sha256sum -c -; }
check "$stage/rndis_host.ko" b6d5f78c65656cd9a1f3660f6174858833ea27a8476eb9c7786396b68aea6c02
check "$stage/mii.ko" c9721be03452297f861da957ac6860b6ca30246f76d5d85e083e1602046b6ec4
check "$stage/cdc_ether.ko" c2fd08495434b92dd616285b60be93b8fb232b052615d942afb1b68e08977a7b
# Do not unload active drivers: other USB adapters may depend on them.
for module in mii cdc_ether rndis_host; do
 if grep -q "^$module " /proc/modules; then
  cmp -s "$stage/$module.ko" "/lib/modules/$module.ko" ||
   fail "$module is already loaded with another/on-disk-unknown version. No changes made. Review manually."
 fi
done
# Refuse to overwrite an existing different custom module without review.
for module in mii rndis_host; do
 if [ -e "/lib/modules/$module.ko" ]; then
  cmp -s "$stage/$module.ko" "/lib/modules/$module.ko" ||
   fail "Existing $module.ko differs. No changes made. Review manually."
 fi
done
[ -f /lib/modules/usbnet.ko ] || fail "System usbnet.ko missing"
backup="/usr/local/lib/rndis-backup/install-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$backup"
for module in mii cdc_ether rndis_host; do
 if [ -f "/lib/modules/$module.ko" ]; then
  cp -p "/lib/modules/$module.ko" "$backup/$module.ko.before"
 else
  touch "$backup/$module.was-absent"
 fi
done
if [ -f /usr/local/etc/rc.d/rndis-drivers.sh ]; then
 cp -p /usr/local/etc/rc.d/rndis-drivers.sh "$backup/rndis-drivers.sh.before"
fi
mkdir -p /usr/local/etc/rndis /etc/udev/rules.d
for rule in /usr/local/etc/rndis/99-rndis-auto-up.rules /etc/udev/rules.d/99-rndis-auto-up.rules; do
 if [ -f "$rule" ]; then
  cp -p "$rule" "$backup/$(echo "$rule" | tr / _).before"
 fi
done
printf '%s\n' 'ACTION=="add", SUBSYSTEM=="net", DRIVERS=="rndis_host", RUN+="/sbin/ip link set dev %k up"' > "$stage/99-rndis-auto-up.rules"
install -o root -g root -m 644 "$stage/99-rndis-auto-up.rules" /usr/local/etc/rndis/99-rndis-auto-up.rules
install -o root -g root -m 644 "$stage/99-rndis-auto-up.rules" /etc/udev/rules.d/99-rndis-auto-up.rules
udevadm control --reload-rules
if [ ! -e /usr/local/lib/rndis-backup/cdc_ether.ko.original ]; then
 cp -p /lib/modules/cdc_ether.ko /usr/local/lib/rndis-backup/cdc_ether.ko.original
fi
for module in mii cdc_ether rndis_host; do
 install -o root -g root -m 644 "$stage/$module.ko" "/lib/modules/$module.ko"
done
cat > "$stage/rndis-drivers.sh" <<'BOOT'
#!/bin/sh
case "${1:-start}" in
start)
 [ "$(uname -r)" = "4.4.302+" ] || { logger -t rndis-drivers "Kernel changed; review modules"; exit 1; }
 mkdir -p /etc/udev/rules.d
 install -o root -g root -m 644 /usr/local/etc/rndis/99-rndis-auto-up.rules /etc/udev/rules.d/99-rndis-auto-up.rules || exit 1
 /bin/udevadm control --reload-rules || exit 1
 for module in mii usbnet cdc_ether rndis_host; do
  if ! grep -q "^$module " /proc/modules; then
   /sbin/insmod "/lib/modules/$module.ko" || exit 1
  fi
 done
 for net in /sys/class/net/*; do
  [ -L "$net/device/driver" ] || continue
  driver=$(readlink "$net/device/driver")
  [ "${driver##*/}" = rndis_host ] || continue
  /bin/udevadm trigger --action=add --subsystem-match=net --sysname-match="${net##*/}" || exit 1
 done
 ;;
stop) : ;;
*) exit 1 ;;
esac
BOOT
install -o root -g root -m 755 "$stage/rndis-drivers.sh" /usr/local/etc/rc.d/rndis-drivers.sh
echo "Backup directory: $backup"
if ! /usr/local/etc/rc.d/rndis-drivers.sh start; then
 echo "ERROR: Module loading failed. Installed files and backup retained for diagnosis." >&2
 dmesg | tail -n 20
 exit 1
fi
echo "Driver installation complete."
lsmod | grep -E '^mii |usbnet|cdc_ether|rndis_host'
# Enable only interfaces whose actual USB driver is rndis_host.
found=0
for net in /sys/class/net/*; do
 [ -L "$net/device/driver" ] || continue
 driver=$(readlink "$net/device/driver")
 [ "${driver##*/}" = rndis_host ] || continue
 iface=${net##*/}
 ip link set dev "$iface" up
 ip addr show dev "$iface"
 found=1
done
[ "$found" = 1 ] || echo "No RNDIS interface found. Check USB device and dmesg."
echo "No DHCP, static IP, DNS or default route configured."
echo "RNDIS interfaces are enabled on net-device add events. DHCP/IP setup is separate."

