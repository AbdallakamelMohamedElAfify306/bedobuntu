# Offline validation: Ubuntu 24.04 (Phosh) for Pixel 7 Pro (cheetah), slot B
Date: 2026-10-28. Host: Linux x86_64 box, no phone attached. Nothing here was run on a real Pixel.
Raw evidence: `offline-validation-artifacts/` (fake fastboot, per-script call logs before/after fix, QEMU serial logs).

## Result table
| # | Test | Result | Evidence |
|---|------|--------|----------|
| 1a | sha256 of ubuntu-userdata.simg.xz | PASS | 8d868a88...bd100ee matches |
| 1b | `xz -t`; decompress | PASS | 1355.8 MiB sparse image, sha256 2c52babd... equals `userdata.simg` in SHA256SUMS |
| 1c | zip: 39 files, SHA256SUMS | PASS | every listed file verifies; only `userdata.simg` is (by design) not in the zip; zip tree == out-ubuntu tree |
| 1d | simg2img, e2fsck, ro mount | PASS | raw 2.44 GiB ext4, label `omamobile-root`, clean, 44683 inodes, Ubuntu 24.04.5 |
| 2a | boot.img | PASS | header v4, kernel 18.4 MB (lz4 -> 43.1 MB arm64 Image, "ARMd", Linux 7.3.0-rc6-omamobile-push1), no ramdisk, no AVB footer (OK for an unlocked bootloader) |
| 2b | init_boot / vendor_boot | PASS | v4 headers, 512-byte cpio ramdisks (stub); vendor_boot cmdline `console=tty0 earlycon=exynos4210,0x10A00000 clk_ignore_unused pd_ignore_unused ... bootconfig` |
| 2c | vendor_kernel_boot | PASS | v4; 7.2 MB lz4 ramdisk (Alpine initramfs: init, e2fsprogs, dropbear, modules); dtb 178,104 B = 2 DTBs, both `google,gs201-cheetah`, model "Google Pixel 7 Pro"; has ufs@14700000, usb@11210000, gpu@28000000, simple-framebuffer |
| 2d | dtbo | PASS | valid DT-table (magic d7b7ab1e), 1 near-empty overlay |
| 2e | sizes vs partitions | PASS (assumed sizes) | boot 18.46 MB, vendor_kernel_boot 7.40 MB, vendor_boot/init_boot 8 KB, dtbo 4 KB. Pixel 7 partition sizes assumed boot/vendor_boot/vendor_kernel_boot 64 MiB, init_boot/dtbo 8 MiB; flash-linux.sh re-checks the real sizes from `getvar all` on the phone and refuses if too big (tested) |
| 3a | shellcheck | PASS (warnings only) | only SC2034 "unused variable" for variables shared via `source`; `bash -n` clean on all scripts |
| 3b | flash-linux.sh with fake fastboot | PASS | writes exactly boot_b, init_boot_b, vendor_boot_b, vendor_kernel_boot_b, dtbo_b, userdata, then `--set-active=b`, `reboot`. 0 writes to any `_a` partition; 0 `erase`/`-w`/`flashing`/`oem`/bootloader/radio/vbmeta/persist/efs calls |
| 3c | flash-linux.sh guards | PASS | refuses: product is-not cheetah, locked bootloader, 0 or 2 phones, bootloader mismatch between slots, unknown bootloader on other slot (needs `--bootloader-slots-match`), image bigger than partition, wrong confirmation, corrupted boot.img (SHA256SUMS). `--dry-run` writes nothing |
| 3d | safe_flash allowlist | PASS | boot_a, vendor_boot_a, bootloader_b, radio_b, persist, efs, vbmeta_b, super, userdata_a all REFUSED |
| 3e | reflash-slot-b.sh | PASS | only the 5 `_b` boot images + set-active=b + reboot, userdata untouched; refuses wrong product/locked; `--with-userdata` forwards to flash-linux.sh |
| 3f | to-android.sh | **FAIL before fix, PASS after** | see bug 1 |
| 3g | to-linux.sh | **FAIL before fix, PASS after** | see bug 1 |
| 3h | check-slot-b.sh | **FAIL (blank values) before fix, PASS after** | see bug 1 |
| 3i | android-protect-from-ota.sh | PASS (logic only) | issues `settings put global ota_disable_automatic_update 1`; whether Google's updater honours it on a real Pixel can't be checked here |
| 4a | grow_root cap | PASS | `etc/omamobile-root-cap` = 47683 MiB (= 49,999,249,408 B < 50 GB). Real `grow_root` function from the shipped init run on a 60 GB loop device: grew 2496 -> 47683 MiB, e2fsck clean. In QEMU the real init with cap 3000 grew the root to 3000 MiB (`df` 2.9G) |
| 4b | mesa-cheetah pinned | PASS | mesa-cheetah 26.2.4 (Mali-G710 patches) Priority 1001; stock mesa packages -10 and replaced/conflicting; panfrost+panthor modules built |
| 4c | firmware | PASS (Mali only) | `/usr/lib/firmware/arm/mali/arch10.8/mali_csffw.bin` present, identical sha256 to build/files. Wi-Fi/BT/audio/haptics firmware is NOT included (Google's, user must run provision-firmware.sh with their factory zip) |
| 4d | fstab / root= | PASS (by design) | no `root=` and fstab empty. The initramfs finds the partition by GPT name `userdata` (PARTNAME) and mounts it (proved in QEMU) |
| 4e | systemd, user | PASS | default.target = graphical.target, phosh enabled; `user` uid 1000 (sudo etc.), password `user` with forced change at first login (worked in QEMU) |
| 4f | qemu-user chroot | PASS | `dpkg --audit` clean (682 pkgs), apt policy OK, `systemd-analyze verify` clean, 0 dangling unit links |
| 4g | QEMU boot, real kernel, rootfs direct | PASS | The shipped 7.3.0-rc6 Image booted on `virt` (virtio-blk/pl011 are built in), systemd reached multi-user and login; ssh, NetworkManager, resolved, phosh active. Only failed unit: `omamobile-boot-success` (expected: no bootloader slot info in QEMU) |
| 4h | QEMU boot, real initramfs -> userdata -> systemd | PASS | Real init (only change: `sda`->`vda` for the virtio test disk, cap 3000): found GPT partition named userdata, e2fsck, grew fs, mounted, `switch_root` to systemd, graphical.target. Board-match guard worked: "simplefb trigger skipped: board is linux,dummy-virt" (it will not poke registers on other boards) |
| 4i | firewall | PASS | nftables rule drops tcp/22 on every interface except usb0/lo (verified live in QEMU) |

## Bugs found
1. **Real bug, fixed**: `scripts/common.sh` `var()` split on ':' so keys containing ':' (`slot-unbootable:a`, `slot-successful:b`, ...) never matched. Effects on a real phone: `to-android.sh` ALWAYS died with "slot A is marked unbootable", `to-linux.sh` ALWAYS died with "slot B is marked unbootable", `check-slot-b.sh` printed empty slot values. flash-linux.sh / reflash-slot-b.sh were not affected (they use sed). Fix: `var()` now matches `key:` as a prefix and trims `: value` / `:value` (works with both fastboot output styles; tested with both). Backups: `$CHEETAH_BUILD/backup-pre-validation/`. SHA256SUMS regenerated for common.sh; zip rebuilt (new sha256 9f6473af...357, 21,824,914 B). **The catbox zip link already given to the user still has the OLD zip; it needs re-uploading (or hand the user the new common.sh).**
2. Documentation/safety notes (not changed): see "Things to know".

## Things to know (honest limits of the build, not bugs I changed)
* **The user's condition "don't erase Android data" is NOT met.** `flash-linux.sh` flashes `userdata`. Android's data was already wiped by the bootloader unlock, but flashing userdata puts Linux's ext4 there, so Android's userdata is gone and Android (slot A, system intact) will show "Can't load Android system / factory reset" if booted. Linux's data is lost when Android reformats userdata. Android and Linux cannot both keep data on one phone with this design (see DUAL_BOOT_ANALYSIS.md: Android userdata is encrypted).
* Slot A's partitions are never written, but a booted Linux runs `omamobile-boot-success`, which writes slot-flag bytes in `devinfo` (via omamobile-bootctl with read-back check) so the bootloader does not abandon slot B. This is upstream Omarchy behaviour; not exercised here.
* Debug SSH key: `$CHEETAH_SSH_KEY` (private) is in the zip and its public key is in `/root/.ssh/authorized_keys` and `/home/user/.ssh/authorized_keys` of the image and in the initramfs (dropbear, root). Mitigated by the nftables rule (usb0 only) and the initramfs is only reachable over the USB cable, but anyone with the zip plus physical USB access can get root. Remove the keys after first login (README item 5).
* Initramfs has a "no USB host in 45 s => panic to fall back to slot A" watchdog; it is killed when the handoff to Ubuntu succeeds, but a very slow first-boot resize without a USB host connected could trip it (the next boot then works because the resize is done). Keep the cable connected to the Mac on first boot.
* DTB bootargs include `omamobile.ufs-probe` (prints a UFS partition report on screen at boot; read-only).
* Phosh in QEMU ran without a GPU (`/dev/dri` absent), so this says nothing about the Mali/panthor path.

## Can ONLY be confirmed on the real phone
1. ABL accepts the images and boots slot B (AVB "orange" state with unsigned images and stock vbmeta_b; images have no AVB footer).
2. The Tensor G2 kernel boots: display (simple-framebuffer / fac00000), UFS enumeration (`ufs@14700000`), USB gadget + the MAX77759 data switch, touch, GPU (panthor/panfrost + Mali firmware), Wi-Fi/BT (needs provision-firmware), audio, battery/charging.
3. UFS storage guard on the real LUNs, and that userdata `sda` partition really is named `userdata` and writable.
4. fastboot on the real bootloader: `getvar all` format, partition sizes, per-slot bootloader versions, max-download-size chunking of the 1.4 GB sparse image, `--set-active=b` behaviour.
5. That slot A still boots after `to-android.sh` (it will after a userdata factory reset) and that Android's retry/rollback logic does not mark slot A/B unbootable.
6. That stopping automatic updates really stops the OTA from overwriting slot B.
7. Boot time/performance, 50 GB cap on real UFS (the cap logic itself is verified).

QEMU success is NOT proof that the Tensor kernel boots, only that the kernel image, initramfs logic and Ubuntu userspace are internally consistent.
