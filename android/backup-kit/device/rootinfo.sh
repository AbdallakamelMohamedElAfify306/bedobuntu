# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=sh
# Runs as root. Read-only facts about the Magisk setup (text).
echo "== magisk version"; magisk -v 2>&1; magisk -V 2>&1
echo "== su grants (policies)"; magisk --sqlite "SELECT * FROM policies" 2>&1
echo "== magisk settings"; magisk --sqlite "SELECT * FROM settings" 2>&1
echo "== denylist (sqlite)"; magisk --sqlite "SELECT * FROM denylist" 2>&1
echo "== ls /data/adb";            ls -laZ /data/adb 2>&1
echo "== ls /data/adb/modules";    ls -laZ /data/adb/modules 2>&1
echo "== ls /data/adb/service.d";  ls -laZ /data/adb/service.d 2>&1
echo "== ls /data/adb/post-fs-data.d"; ls -laZ /data/adb/post-fs-data.d 2>&1
echo "== ls /data/local/tmp";      ls -laZ /data/local/tmp 2>&1
