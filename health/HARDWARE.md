# Pixel 7 Pro (cheetah / gs201) hardware status, as of 2026-10-29

Sources: Omarchy Mobile docs/DEVICES.md and docs/ROADMAP.md (github.com/derekross/omarchy-mobile, ROADMAP last updated
2026-10-26), Android AOSP eSIM docs (source.android.com/docs/core/connect/esim-overview), android-se-access (eUICC access
rules), lpa-gtk / lpac notes (AT-backend eSIM on removable eUICCs). UBports (Ubuntu Touch) has no Pixel 7 Pro port.
postmarketOS wiki could not be fetched (HTTP 403) and was NOT used as a source.

The kernel on this phone (7.3.0-rc6-omamobile-push1) is Omarchy Mobile's. Their USERSPACE is Arch packages
(omamobile-aoc, -audio, -sensors, -gnss, -fingerprint, -modem, -mmd, omacam, libcamera 0.7.x patched...). This Ubuntu
image installs only the kernel modules + omamobile-device-cheetah + Mesa 26.2.4 (mesa-cheetah). So "kernel works upstream"
does NOT mean "works in this Ubuntu".

| subsystem | upstream (Omarchy) | in THIS Ubuntu image | what is possible |
|---|---|---|---|
| display 120 Hz, touch, buttons | works | works (you see it) | nothing to do |
| GPU Mali-G710 | works (panthor + patched Mesa) | mesa-cheetah installed | verify with 40-hw-check.sh (renderD node + panfrost mapped by phoc) |
| Wi-Fi BCM4389, Bluetooth | works (needs Google firmware) | needs firmware from YOUR factory image | provision-firmware.sh from the build kit, on a PC/Docker |
| battery/charging | works | kernel driver present | upower icon needs upower service |
| speakers/mics | partial (quiet, thin) | NOT installed (needs AoC firmware boot + omamobile-audio) | porting work, not a command |
| sensors (accel/light/prox/compass) | works | NOT installed (omamobile-sensors) | porting work |
| GPS | works (Google GNSS stack in a chroot) | NOT installed | porting work; geoclue exists in Ubuntu |
| NFC tags | works | NOT installed (neard patched, not in noble) | porting work; card emulation/payments never |
| fingerprint | works, opt-in | NOT installed | needs Google HAL chroot + Trusty TA; skip |
| camera | works with caveats: all 4 sensors via patched libcamera 0.7.x and the omacam app; telephoto fixed-focus; basic quality | camera timer deliberately removed in build; noble libcamera has no gs201 pipeline | not available now |
| modem / calls / SMS / data | WIP: modem boots to ONLINE, no SIM test yet | not exposed | not available now |
| eSIM | n/a | n/a | impossible on Linux today: built-in eUICC is reachable only through Android's privileged LPA; lpac needs an APDU channel from a working modem (AT/QMI) and is not in Ubuntu noble. Manage the eSIM from Android. A removable eUICC card is a different thing |
| suspend/deep sleep | s2idle experimental, ~16 h standby; no deep sleep | enable-suspend off by default | none |
