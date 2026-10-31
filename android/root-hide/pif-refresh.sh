# SPDX-License-Identifier: GPL-3.0-or-later
# Run with: bash pif-refresh.sh
sleep 90
F=/data/adb/modules/playintegrityfix/custom.pif.prop
if { [ -f "$F"  ]; [ $? -ne 0 ]; } || [ -n "$(find "$F" -mtime +7)" ]; then
  sh /data/adb/modules/playintegrityfix/autopif4.sh --strong
  sh /data/adb/modules/playintegrityfix/killpi.sh
fi
