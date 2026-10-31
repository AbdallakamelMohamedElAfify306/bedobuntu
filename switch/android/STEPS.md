# Pixel 7 Pro: Magisk root (slot A only) + "التبديل إلى Ubuntu" icon
Date 2026-10-29. Nothing here was run on the phone. Mac = zsh, no bang characters anywhere.
Files: SwitchToUbuntu.apk (built, debug-signed), app/ (source), build.sh, research/ (Magisk 31.1 APK, release notes, stock init_boot hash).

## Facts used
- Magisk latest stable = v31.1 (2026-10-25, 4 days old). APK sha256 89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7. v31.1 has NO root pop-up any more: an app only gets su after you switch it on in Magisk > Superuser. v30.7 (2026-02-23) is the previous stable.
- Newest public Pixel 7 Pro build = Android 17 CP3A.261005.002.A1 (factory zip sha256 5b5b06ad...b8; stock init_boot.img sha256 37afe1b9b5b101c5e5a90878b09ff4744aedafbc22dd986d4b293e408875ad01, 8388608 bytes). Your phone may be on an older build: the init_boot MUST be from YOUR build id.
- Magisk preinit storage = an already-mounted partition (/data, /cache, /metadata, /persist by priority; native/src/core/mount.rs). It can never pick `ubuntu`.
- Boot HAL: Magisk's APK carries a prebuilt AOSP `bootctl` (lib/arm64-v8a/libbootctl.so, AOSP android-14 build, API 31+). It talks to the real boot-control HAL. On Pixel (gs-common AIDL HAL) setActiveBootSlot(1) = b.active=1/a.active=0, b retry=3 unbootable=0 successful=0 in devinfo, then writes UFS bBootLunEn=2 through sysfs pixel/boot_lun_enabled. Same effect as `fastboot --set-active=b`.
- /system/bin/bootctl is NOT on user builds (that is why the APK bundles one).

## GOAL 1 - root (writes ONE partition: init_boot_a)
Needs: phone on Android (slot a), USB cable, USB debugging on (Settings > About phone > tap Build number 7 times > Developer options > USB debugging).

1. `adb devices`
   Expect: serial then `device`. STOP if `unauthorized` (accept the prompt on the phone) or empty.
2. `adb shell getprop ro.boot.slot_suffix; adb shell getprop ro.build.id; adb shell getprop ro.build.fingerprint`
   Expect: `_a`, a build id like `CP3A.261005.002.A1`, a fingerprint `google/cheetah/cheetah:17/<id>/...:user/release-keys`. STOP if slot_suffix is `_b`. Write the build id down.
3. Download the factory zip of THAT build (list: https://developers.google.com/android/images , section "Pixel 7 Pro"; check the SHA-256 printed there). For the newest build: `mkdir -p $HOME/cheetah-dual/root && cd $HOME/cheetah-dual/root && curl -L -O https://dl.google.com/dl/android/aosp/cheetah-cp3a.261005.002.a1-factory-5b5b06ad.zip && shasum -a 256 cheetah-cp3a.261005.002.a1-factory-5b5b06ad.zip`
   Expect for that file: `5b5b06adb6566e20b927e887f42222f7387d25d37a3257b5f4655bb905aacdb8`. STOP if the hash differs, or your build id is not on Google's page (tell me, there is an OTA route).
   WARNING: never run flash-all.sh / flash-base.sh from this zip: it wipes data, rewrites the bootloader and the GPT (kills the `ubuntu` partition entry). We only take one file out of it.
4. Extract only init_boot.img: `cd $HOME/cheetah-dual/root && unzip -o cheetah-*-factory-*.zip '*/image-cheetah-*.zip' -d fx && unzip -o fx/*/image-cheetah-*.zip init_boot.img -d img && ls -l img/init_boot.img && shasum -a 256 img/init_boot.img`
   Expect: 8388608 bytes. For build CP3A.261005.002.A1 the hash is `37afe1b9b5b101c5e5a90878b09ff4744aedafbc22dd986d4b293e408875ad01`. STOP if size differs.
5. Magisk APK: `cd $HOME/cheetah-dual/root && curl -L -o Magisk-v31.1.apk https://github.com/topjohnwu/Magisk/releases/download/v31.1/Magisk-v31.1.apk && shasum -a 256 Magisk-v31.1.apk && adb install Magisk-v31.1.apk`
   Expect: `89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7`, then `Success`. STOP if the hash differs. (Fallback if v31.1 misbehaves: v30.7 from the same releases page.)
6. `adb push $HOME/cheetah-dual/root/img/init_boot.img /sdcard/Download/init_boot.img`
   Expect: `1 file pushed`.
7. On the phone: Magisk app > Install > "Patch firmware / image" (Select from storage) > pick init_boot.img > Let's go. Do NOT use "Download latest Pixel factory image" (needs Wi-Fi and may pick a newer build) and NEVER choose "Install to inactive slot".
   Expect: log ends `- All done.` and a file /sdcard/Download/magisk_patched-<ver>_<rand>.img. STOP on any red error line.
8. `P=$(adb shell 'ls -t /sdcard/Download/magisk_patched-*.img | head -1' | tr -d '\r') && adb pull "$P" $HOME/cheetah-dual/root/magisk_patched.img && ls -l $HOME/cheetah-dual/root/magisk_patched.img`
   Expect: size at most 8388608 (normally a bit smaller or equal). STOP if bigger than 8388608.
9. `adb reboot bootloader` then `fastboot getvar current-slot 2>&1 | head -1; fastboot getvar unlocked 2>&1 | head -1; fastboot getvar partition-size:init_boot_a 2>&1 | head -1`
   Expect: `current-slot: a`, `unlocked: yes`, `partition-size:init_boot_a: 0x800000`. STOP otherwise.
10. `fastboot flash init_boot_a $HOME/cheetah-dual/root/magisk_patched.img`
    Expect: `Sending 'init_boot_a'`, `OKAY`, `Writing 'init_boot_a'`, `OKAY`, `Finished`. Always with the explicit `_a`. Do not flash anything else (no vbmeta, no --disable-verity, no set-active). STOP on FAILED.
11. `fastboot reboot`
    Android starts as before (orange unlocked-bootloader screen is normal). Data is untouched. If it bootloops: fastboot, then `fastboot flash init_boot_a $HOME/cheetah-dual/root/img/init_boot.img` (stock one from step 4) and `fastboot reboot`; send me what you saw.
12. Phone: open Magisk. If it says "Requires additional setup", accept (it reboots once). Home must show Installed = 31.1 and Ramdisk = Yes. Then Superuser tab: switch ON "Shell" (needed only for adb tests).
13. `adb shell su -c id`
    Expect: `uid=0(root) gid=0(root) groups=0(root) context=u:r:magisk:s0`. If `not allowed`: Shell not switched on in Superuser tab.
14. `adb shell getprop ro.boot.slot_suffix`
    Expect: `_a`. Slot B was never touched by any command above.
15. Optional hardening against an accidental OTA: `adb shell settings put global ota_disable_automatic_update 1` (same as Developer options > Automatic system updates = off).

Warnings: (a) Unlocked bootloader already fails Play Integrity "device" level; root and Magisk can make banking apps, Google Wallet tap-to-pay, some streaming apps refuse to run. v31.1 removed app hiding; I cannot promise any fix. (b) An Android OTA while on slot a installs into slot B (inactive) = overwrites Ubuntu's boot images, and removes root from a. Updates stay off. (c) Never tap "Install to inactive slot" in Magisk. Magisk's own update: use Direct Install (current slot only). (d) Never `fastboot flashing lock`.

### Android must not touch sda32 (`ubuntu`) - assessment
- No fstab entry (fstab.gs201 mounts only listed partitions: /data = userdata, /metadata, /vendor_dlkm etc.). fs_mgr never looks at unknown partitions.
- Factory reset / "wipe data" only formats `userdata` and `metadata`; `userdata` is now sda31 by name.
- vold manages only removable/adopted disks; fstrim/idle maintenance only on mounted filesystems; storaged only reads.
- Boot HAL writes devinfo and the UFS boot-LU attribute only; its GPT fallback would only run if devinfo were invalid (it is valid, header DEVI 3.15). If it ever did, it rewrites boot_a/boot_b attribute bits and the header CRC; it reads the entry count from the header (no hard-coded 31) - read in source, not run on a device.
- Magisk root can of course dd anything; only your own commands or modules would do that. Magisk itself writes `/data/adb` and a small dir in a MOUNTED partition (/metadata or similar), never `ubuntu`.
- What DOES hit it: a factory flash (flash-all, `fastboot flash bootloader`/partition:0..3) rewrites the GPT and drops the `ubuntu` entry (data stays on flash; restore with the gptSPLIT backup); `fastboot erase`/`flash ubuntu` typed by you.
- Check after root (read-only): `adb shell su -c 'ls -l /dev/block/by-name/ubuntu; grep -E "sda32|by-name/ubuntu" /proc/mounts; echo mounts=$?'`   Expect: a symlink to /dev/block/sda32, no mount line, `mounts=1`.
Confidence: high that stock Android does not write it, medium-high for root use (depends on you).

## GOAL 2 - home-screen icon (APK, root through Magisk, HAL path)
Design: tiny app with no permissions, label `التبديل إلى Ubuntu`. Tap -> dialog (3 buttons: تبديل وإعادة تشغيل / إلغاء / اختبار فقط). It runs `su -c <script>` (app/res/raw/switch_to_ubuntu.sh):
 find a working bootctl (bundled libbootctl.so, else /data/adb/magisk/bootctl, else /system/bin/bootctl, each tested with hal-info) -> refuse unless current slot = 0 -> refuse unless a partition named `ubuntu` exists -> refuse unless slot b is bootable -> `set-active-boot-slot 1` -> read back `get-active-boot-slot` must be 1 (else it puts slot 0 back and stops) -> sync -> reboot.
 No raw devinfo/UFS writes anywhere. Exit codes: 0 ok, 11 no bootctl, 13 not on slot a, 14 set failed, 15 read-back mismatch (reverted), 16 no ubuntu partition, 17 slot b unbootable; anything else = su not granted.
Interference check (source): markBootSuccessful touches only the running slot; update_engine only calls setSlotAsUnbootable/setActive during an OTA (updates are off); Android never marks slot b unbootable on its own. After the HAL call b has retry=3, successful=0; Ubuntu's omamobile-boot-success.service marks b successful at boot (already enabled), so ABL's retry counter is harmless.
Alternatives rejected: Magisk module action.sh = a button inside the Magisk app only, no home icon; Termux + Termux:Widget = 3 extra installs (F-Droid, Termux, Widget), no confirmation dialog, same su grant. A direct devinfo write from Android = unnecessary risk.

16. Install: `adb install $HOME/cheetah-dual/SwitchToUbuntu.apk` (file from $CHEETAH_SWITCH/android/SwitchToUbuntu.apk, sha256 in the final report).
    Expect: `Success`. STOP on `INSTALL_FAILED_...`.
17. Phone: Magisk > Superuser tab > switch ON "التبديل إلى Ubuntu".
18. Read-only check without the app UI (tests that the bundled bootctl runs on this Android build):
    `adb shell su -c 'L=$(ls /data/app/*/org.cheetah.switchtoubuntu-*/lib/arm64/libbootctl.so); $L hal-info; $L get-current-slot; $L get-active-boot-slot; $L is-slot-bootable 1'`
    Expect: `HAL Version: android.hardware.boot@aidl::IBootControl` (or a 1.x line), `0`, `0`, `1`. STOP if hal-info fails (then send me the text; fallback = the Mac command `fastboot --set-active=b`).
19. Tap the new icon > "اختبار فقط".
    Expect: `TEST OK: nothing was changed` and `exit code: 0`. STOP on `ERR 1x` or a su message (switch it on in Superuser, step 17).
20. READY CHECK before the real switch: Ubuntu must be in a good state (slot b boots; you tested that already) and the Mac with fastboot is at hand. Tap the icon > "تبديل وإعادة تشغيل".
    Expect: reboot, Ubuntu (Phosh) comes up from sda32. Then on the Mac: `ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'findmnt -no SOURCE /; switch-slot status | head -8'`  Expect: `/dev/sda32`, running slot b. If the phone does not come up in 3 minutes: hold Vol-Down + Power to fastboot, `fastboot --set-active=a` or `--set-active=b` as before.

Rebuild: `cd $CHEETAH_SWITCH/android && ./build.sh` (JDK 17 in ~/sdk, SDK platform 34 + build-tools 34.0.0 on this box). Debug key = android/debug.keystore (pass android).

## Risk / confidence
- Root: init_boot_a only, reversible by flashing the stock init_boot_a, no data wipe. Confidence 85%. Unknowns: Magisk 31.1 is 4 days old and Android 17 is new (v31.0 added Zygisk for A17; plain su/boot patching is the stable part). Slot B untouched by construction.
- Icon: built and aligned/signed, script logic tested against a fake bootctl on this box (dry run + real path + reboot call), NOT run on a phone. Confidence 75% it works first try; main unknown is whether the bundled AOSP-14 bootctl runs on A17 and whether Magisk lets it exec (step 18 tests exactly that, read-only). Failure modes are safe: all refusals happen before any write.
