# Pixel 7 Pro (cheetah) slot switcher

Files: switch-slot (Ubuntu, root), switch-slot.gz.b64 / cmd-install.txt (single-line ssh install), cmd-diagnostic.txt (read-only),
switch-to-android.desktop + cmd-launcher.txt (optional Phosh launcher), src/ (upstream sources used), test/ (x86 test harness + synthetic devinfo).

## Where slot state lives (cheetah / gs201)
- devinfo partition (8 KiB, unslotted), first 128 bytes: "DEVI", u16 ver 3 . u16 15, then 4 bytes per slot at 0x30 (a) and 0x34 (b):
  retry_count, flags (bit0 unbootable, bit1 successful, bit2 active, bit3 fastboot_ok), 2 unused. HAL rule: active slot = b if slots[1].active else a.
  Sources: android.googlesource.com/device/google/gs-common bootctrl/aidl/{DevInfo.h,BootControl.cpp} (main + android-14.0.0_r75), device/google/gs101 interfaces/boot/1.2;
  Omarchy Mobile device/cheetah/NOTES.md (2026-10-11: the phone's own backup decodes exactly to `fastboot getvar all`).
- GPT attributes on boot_a/boot_b are only the HAL fallback when devinfo is absent or < 3.3 (bits 52-53 prio, 54 active, 55-57 retry, 58 successful, 59 unbootable). NOT used here. Do not sgdisk.
- UFS attribute bBootLunEn (1 = boot LU A, 2 = boot LU B) selects which bootloader copy runs; HAL setActiveBootSlot writes it. Mainline exposes it read-only in sysfs, so a write needs a raw UPIU via /dev/bsg/ufs-bsg0 (CONFIG_SCSI_UFS_BSG=y is set in our kernel).
- setActiveBootSlot(slot): other.active=0; slot: retry=3, unbootable=0, successful=0, active=1, fastboot_ok=0. markBootSuccessful: slot.successful=1 (Android also burns anti-rollback fuses; Linux does not).
- Ubuntu already ships omamobile-bootctl and omamobile-boot-success.service (enabled) which marks slot B successful each boot, so ABL does not burn its retries.

## Hard limit to tell the user
Linux root = the userdata partition. Android cannot read it and will format it (or demand a factory reset). So A <-> B is not a free toggle:
Ubuntu -> Android destroys Ubuntu's data; Android -> Ubuntu only works if Android has not booted since (to-linux.sh checks), otherwise flash-linux.sh again.
