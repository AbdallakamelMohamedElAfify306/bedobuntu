# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash android-protect-from-ota.sh
# Run with Android booted (slot A), USB debugging on, phone connected. Turns off automatic system updates so Android's
# OTA cannot overwrite the inactive slot (slot B = Linux). Also check Settings > System > Software updates by hand.
# Needs redoing after every Android factory reset (the setting lives in Android's userdata).
set -euo pipefail
command -v adb >/dev/null || { echo "adb not found (platform-tools)"; exit 1; }
adb shell settings put global ota_disable_automatic_update 1
echo "ota_disable_automatic_update = $(adb shell settings get global ota_disable_automatic_update)"
cat <<'MSG'
Also do this by hand (Android UI differs by version):
  Settings > System > Developer options > turn OFF "Automatic system updates"
  Settings > System > Software updates > do NOT tap "Download and install"
  Keep Android offline (Wi-Fi off) if you rarely use it. Never accept a system-update notification.
If an update slips through, run scripts/check-slot-b.sh then scripts/reflash-slot-b.sh.
MSG
