# Restore safety (same Pixel 7 Pro, same build CP3A.261005.002.A1, Android slot a, Magisk root)
| Item | Backed up from | Restore on same device | Notes |
|---|---|---|---|
| settings list system/secure/global (text) | `settings list` | SAFE (selective) | Reference only; re-apply individual keys with `settings put <ns> <key> <val>`. Don't bulk replay secure/global (contains device-specific ids, setup state, ADB/dev flags). |
| Raw settings_*.xml + /data/system/users/0/*.xml (ABX) | /data/system/users/0 | NOT RECOMMENDED | Live system_server rewrites them; a file swap needs the system stopped (recovery) and can bootloop or break app SSAIDs (settings_ssaid.xml), package-restrictions, appwidgets. Kept as a disaster record only; no restore script provided. |
| Wi-Fi WifiConfigStore.xml, /data/misc/wifi | apexdata/com.android.wifi | SAFE | Wi-Fi off first, owner system:wifi + restorecon, reboot. Contains saved passwords. |
| Bluetooth /data/misc/bluedroid | bluedroid / bluetooth | CAUTION | Works on same device only, BT off first, then reboot; if a pairing misbehaves, forget and re-pair. Contains link keys. |
| Pixel Launcher data | /data/data + /data/user_de nexuslauncher | SAFE | Same launcher version; force-stop, restore, restorecon, reboot. |
| Wallpaper wallpaper* | /data/system/users/0/wallpaper* | SAFE | Restore wallpaper + wallpaper_info.xml together, reboot. |
| Accounts (names only) | dumpsys account | N/A | List only, no tokens; re-add accounts by signing in. |
| roles.xml (default apps) | users/0 or misc_de/0/apexdata/com.android.permission | SAFE | Or re-set via Settings > Default apps. File is at the apex path on Android 12+; script grabs both. |
| Notification policy | /data/system/notification_policy.xml | SAFE | Reboot after restore. |
| Gboard data | com.google.android.inputmethod.latin | SAFE | Force-stop first; contains personal dictionary, so keep the backup private. |
| Clock/alarms | com.google.android.deskclock | SAFE | Force-stop first; alarms are re-armed on boot. |
