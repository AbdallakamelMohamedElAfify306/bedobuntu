# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash test-network.sh
# Offline mock test for 20-fix-network.sh in a private network namespace (dummy usb0 + wlan0; nothing real is touched).
KIT=$(cd "$(dirname "$0")/.." && pwd)
exec unshare -rmn bash -c '
KIT='"$KIT"'
T=$(mktemp -d); mkdir -p $T/bin $T/etc $T/h
cp -a /etc/. $T/etc/ 2>/dev/null; mount --bind $T/etc /etc; mount -t tmpfs tmpfs /usr/local; mkdir -p /usr/local/sbin /etc/NetworkManager/dispatcher.d
printf "# run-with bash\nexit 0\n" > $T/bin/systemctl; chmod +x $T/bin/systemctl
ip link set lo up
ip link add usb0 type bridge; ip link add wlan0 type bridge; ip link set usb0 up; ip link set wlan0 up
ip addr add 172.16.42.1/24 dev usb0; ip addr add 192.168.1.50/24 dev wlan0
ip route add default via 172.16.42.2 dev usb0 metric 100 onlink
ip route add default via 192.168.1.1 dev wlan0 metric 600 onlink
export PATH=$T/bin:$PATH HEALTH_TEST=1 HEALTH_DIR=$T/h WIFI_IFACE=wlan0
echo "### before"; ip route
echo "### check"; bash $KIT/20-fix-network.sh --check | grep -E "^\[(DRY|WARN|FAIL)\]|RESULT"; ip route | grep -c "dev usb0.*default\|default.*usb0"
echo "### apply"; bash $KIT/20-fix-network.sh --apply | grep -E "^\[(OK|WARN|FAIL)\]|RESULT"
echo "### after"; ip route
echo "### run installed fix script when both defaults exist"; ip route add default via 172.16.42.2 dev usb0 metric 100 onlink
# the installed fix detects wifi via sysfs; emulate by sed-patching a copy for the test only
sed "s#if \[ -d \"\$d/wireless\" \] || \[ -d \"\$d/phy80211\" \]; then wl=\$(basename \"\$d\"); break; fi#wl=wlan0#" /usr/local/sbin/cheetah-route-fix > $T/fix; sh $T/fix; ip route
sh -n /usr/local/sbin/cheetah-route-fix && echo FIX_SYNTAX_OK; sh -n /etc/NetworkManager/dispatcher.d/90-cheetah-route-fix 2>/dev/null; ls -la /etc/NetworkManager/dispatcher.d/ /etc/systemd/system/cheetah-route-fix.service
echo "### apply again"; bash $KIT/20-fix-network.sh --apply | grep -E "^\[(WARN|FAIL)\]|already|RESULT"
'
