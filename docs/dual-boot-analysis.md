# Android on slot A + Linux on slot B, both keeping their data: is it possible on a Pixel 7 Pro (cheetah)?

Verdict: **No safe option exists. This package therefore installs Linux on slot B and uses all of `userdata` for it.**
Android's *system* stays intact on slot A and can be re-activated with `fastboot --set-active=a`, but Android's *data* is
erased by the install, and Linux's data is lost when Android boots again and formats `userdata`. Nothing in this package
writes the GPT, the bootloader, or any partition outside the allowlist `boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata`.

Status of the evidence: [V] = read in Omarchy Mobile code/docs in `src/omarchy-mobile`, [P] = public documentation or reports,
[I] = inference. Nothing was tested on a phone.

## (a) An ext4 image file inside Android's userdata, loop-mounted by the Linux initramfs
Not viable.
* Cheetah's userdata is f2fs with file-based encryption plus metadata encryption using hardware-wrapped keys (`wrappedkey_v0`)
  [P: AOSP metadata-encryption / hardware-wrapped-key docs; I: Pixel 7 uses them. Not confirmed from a cheetah fstab in this session]. The key is wrapped by the Tensor security
  hardware and only unsealed by Android's `vold` after the user's lock-screen credential. Our initramfs can neither mount f2fs
  userdata (the raw device is ciphertext) nor create/find an image file in it: file *names and contents* are encrypted.
* Even a plaintext file would not be possible: the device is encrypted at block level before any filesystem can be read [P].
* Android's fstab marks userdata `formattable`-style: if it cannot mount it, first boot formats it, or recovery offers a factory reset [P/I]. Any attempt to open it from Linux with a different key state risks exactly that.
* Omarchy does not do this: it replaces userdata with its own ext4 root and says so ("installing erases `userdata`, which holds stock
  Android's data") [V: README.md "Quick start", device/husky/UFS-PLAN.md].

## (b) Shrink userdata and add a Linux partition (GPT edit)
Not safe, so not implemented.
* On Pixels the GPT is *rewritten by bootloader flashing*: the bootloader "pack" flash writes `partition:0..3` GPT copies; a wrong
  or stale table makes the phone un-bootable [P: AOSP/Pixel factory-image flash-all scripts; I]. In Omarchy's tree: Pixel 4-family slot flags live in GPT attributes and writing them is "a narrow, named exception" [V: CONTRIBUTING.md:60-70, AGENTS.md:13]; on cheetah the slot state lives in `devinfo`, not the GPT [V: device/cheetah/NOTES.md:242], so Omarchy never needs to touch the GPT here.
* There is no supported on-device tool to resize a partition that holds an encrypted f2fs filesystem, and `fastboot` cannot resize
  partitions on this device (only dynamic partitions inside `super` can be edited, and userdata is not one) [P].
* Writing the GPT from Linux (sgdisk) on UFS LUN 0 changes the table that the Tensor G2 boot ROM/ABL read (the primary and backup copies
  across LUNs); public reports of hard-bricked Pixels after wrong bootloader/partition-table flashes exist [P: general XDA/Reddit reports; I did not pin down a specific thread, so treat this as unverified]. Recovery then would need a service tool, not fastboot [I].
* Omarchy deliberately forbids this: its initramfs storage guard makes every UFS partition read-only except the allowlist, and removes the
  whole-disk node (`/dev/sda`) so nothing can touch the GPT [V: initramfs `init`, CONTRIBUTING.md:70 "only exceptions are an allowlist of GPT partition names: BOOT_IMAGES on slot B, and userdata"].
* The user's brief says: under no circumstances generate steps that brick the GPT or the bootloader. This option cannot meet that.

## (c) A spare / unused partition
None suitable.
* Pixel 7 Pro partitions that are not slot-A/B system or critical (`userdata`, `metadata` 16 MB, `persist`, `efs`, `modem_userdata`,
  `misc`, `frp`, logs, etc.) are either needed by Android, hold device-unique data (calibration, modem NV, IMEI), or are tiny [I; Omarchy only allowlists its own 5 slot-B images + userdata, device/cheetah/device.conf]. Using them risks losing radio/sensor calibration irreversibly.
* `super` (dynamic partitions, several GB for slot A + B) is the only large area besides userdata; slot B's half is reserved by A/B OTA, and
  Android's OTA/virtual-A/B snapshot logic writes there (and would overwrite Linux).
* A USB-C flash drive as the Linux root would avoid all of this, but USB *host* mode on cheetah is "design only" in Omarchy
  [V: device/cheetah/USB-C-PLAN.md section B4c]: not implemented.

## (d) What Omarchy and others document
* Omarchy: slot B boot images + userdata replaced; stock Android on slot A is "the way back" (and that way back reinstalls/reformats data) [V: README.md,
  CONTRIBUTING.md section on flashing, device/cheetah/REINSTALL-RUNBOOK.md].
* postmarketOS on Pixels / Droidian / UBports on other phones: either full userdata replacement, or an image in the Android `userdata` on
  *unencrypted* old devices. No published dual-boot with retained Android data for Tensor devices was found [P].

## What the package provides instead (to make switching and recovery as safe as it can be)
* `scripts/flash-linux.sh`: allowlist-only writes, product/unlock/bootloader-match/size checks, two typed confirmations, `--dry-run`.
* `scripts/to-android.sh`: `--set-active=a` only. Android will format the Linux userdata (it cannot read it); that is the price.
* `scripts/to-linux.sh`: refuses unless Linux was the last thing installed and Android has not booted since.
* `scripts/reflash-slot-b.sh`: re-flashes only the 5 slot-B boot images (keeps Linux data) after an Android OTA overwrote slot B.
* `scripts/check-slot-b.sh`: read-only slot status.
* `scripts/android-protect-from-ota.sh` + README: disable automatic system updates so OTA does not write slot B.
* The bootloader's A/B fallback: if slot B fails 3 boots the bootloader switches back to slot A by itself [P: Android A/B boot control retry counter; V: Omarchy's omamobile-boot-success/bootctl units mark success]. The retry count on cheetah is held in `devinfo` [V: NOTES.md:242].
