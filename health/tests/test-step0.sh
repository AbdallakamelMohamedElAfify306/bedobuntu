# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash test-step0.sh
# Offline mock test for 00-step0-undo-wallpaper.sh (runs in a user namespace with fake /opt and /etc; touches nothing real).
# Usage: bash tests/test-step0.sh
KIT=$(cd "$(dirname "$0")/.." && pwd)
exec unshare -rm bash -c '
set -u
KIT='"$KIT"'
T=$(mktemp -d); mkdir -p $T/bin $T/etc $T/h
cp -a /etc/. $T/etc/ 2>/dev/null; mount --bind $T/etc /etc
mount -t tmpfs tmpfs /opt
mkdir -p /opt/phosh-overlay/sm/puri/phosh/stylesheet /opt/phosh-overlay/sm/puri/phosh/ui /etc/systemd/system/pixel-phosh.service.d /etc/systemd/system/phosh.service.d
echo css > /opt/phosh-overlay/sm/puri/phosh/stylesheet/adwaita-dark.css; echo x > /opt/phosh-overlay/sm/puri/phosh/stylesheet/adwaita-dark.css.bak-lock
echo ui > /opt/phosh-overlay/sm/puri/phosh/ui/top-panel.ui
echo "[Service]" > /etc/systemd/system/pixel-phosh.service.d/20-clock-right.conf
echo "[Service]" > /etc/systemd/system/pixel-phosh.service.d/zz-wallpaper.conf
echo "[Service]" > /etc/systemd/system/phosh.service.d/zz-wallpaper.conf
echo new > /etc/cheetah-test.conf; echo orig > /etc/cheetah-test.conf.bak-wall
cp /bin/sleep $T/bin/phosh
cat > $T/bin/systemctl <<S
# run-with bash
case "\$1" in
  cat) exit 0 ;;
  daemon-reload) exit 0 ;;
  restart) pkill -x phosh; sleep 0.5; G_RESOURCE_OVERLAYS=/sm/puri/phosh/ui=/opt/phosh-overlay/sm/puri/phosh/ui setsid $T/bin/phosh 300 >/dev/null 2>&1 & sleep 1; exit 0 ;;
esac
exit 0
S
chmod +x $T/bin/systemctl
export PATH=$T/bin:$PATH HEALTH_TEST=1 HEALTH_DIR=$T/h
G_RESOURCE_OVERLAYS=/sm/puri/phosh/ui=/opt/phosh-overlay/sm/puri/phosh/ui:/sm/puri/phosh/stylesheet=/opt/phosh-overlay/sm/puri/phosh/stylesheet setsid $T/bin/phosh 300 >/dev/null 2>&1 &
sleep 1
echo "##### CHECK"; bash $KIT/00-step0-undo-wallpaper.sh --check | grep -E "^\[(DRY|WARN|FAIL)\]|RESULT"
echo "##### APPLY"; bash $KIT/00-step0-undo-wallpaper.sh --apply | grep -E "^\[(OK|WARN|FAIL)\]|RESULT"
echo "##### APPLY AGAIN (idempotent)"; bash $KIT/00-step0-undo-wallpaper.sh --apply | grep -E "^\[(WARN|FAIL)\]|RESULT"
echo "##### state"; find /opt -type f; ls /etc/systemd/system/*.d/; cat /etc/cheetah-test.conf; find $T/h/backup | head -20
pkill -x phosh
'
