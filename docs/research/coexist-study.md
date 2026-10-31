# Moving Ubuntu's rootfs off `userdata` — study (cheetah / Pixel 7 Pro)
Date: 2026-10-29. Nothing was run on the phone. Evidence tags: [S] = primary source read, [D] = project docs/code on the Mac-box, [I] = my inference (unverified), [U] = unknown.

## 0. Bottom line
* The wipe is caused by the **content of `userdata`**, not by `misc`/bootloader. Android's `/data` must be f2fs + FBE + metadata-encryption with a key in `/metadata`. Ubuntu's ext4 in that partition fails the mount, so Android goes to recovery "Can't load Android system / Factory data reset".
* Whatever we do, **Android needs one fresh userdata** (the current one is Ubuntu's). Because userdata is already lost, now is the cheapest moment to restructure.
* The only in-phone, fast option that Android never touches: **(a) shrink `userdata`, add our own partition (e.g. `ubuntu`, ≤50 GB) behind it.** Confidence: medium-low (works on other UFS phones; no confirmed Tensor precedent found).
* **"Survive OTA" cannot be fully met by any option**: Virtual A/B OTA overwrites slot B's *boot images* no matter where the rootfs lives. The rootfs/data survive; the 5 boot images need a ~1 min re-flash (or block OTA). See §4.
* (e) USB SSD: safest for Android, but fails "fast/smooth" (USB 2.0 only today) and host mode / VBUS isn't implemented yet.

## 1. Why Android wipes
1. gs201 fstab (`fstab.gs201.in`) [S]: `/data` = f2fs, `latemount,wait,check,quota,formattable,checkpoint=fs, fileencryption=..., metadata_encryption=..., keydirectory=/metadata/vold/metadata_encryption`.
2. `fs_mgr_mount_all` [S]: mount fails (ext4 ≠ f2fs). It auto-formats only if `partition_wiped()` — first 4096 bytes all 0x00 or all 0xFF — (or encryption was interrupted). An ext4 superblock is at +1024, so it is NOT "wiped" → no auto format.
3. Mount failure → `FS_MGR_MNTALL_FAIL` → init reboots to recovery with `--prompt_and_wipe_data` [I from search synthesis of init/builtins.cpp; I did not read builtins.cpp itself]. User confirms → recovery formats userdata+metadata → normal boot.
4. `misc` plays no part in the decision. Slot state is in `devinfo` [D/S].
5. Answer to "would it still happen if Ubuntu lives elsewhere": **yes once** — Android's userdata is currently ext4. If, however, the new `userdata` is *blank* (zero first 4 KiB, e.g. `blkdiscard`/`dd`), `partition_wiped()` is true and Android formats it itself on first boot **without** the recovery prompt [I; prompt-less path likely but unverified; worst case = one "Factory data reset" tap, no data to lose].
6. Android Factory reset afterwards only formats userdata/metadata → a separate Ubuntu partition survives resets [I].

## 2. Options
| | Option | Verdict | Why |
|---|---|---|---|
| a | Shrink `userdata` (GPT), add `ubuntu` partition | **Viable, recommended** | Android has no fixed userdata size in fstab; AVB doesn't cover userdata; Ubuntu gets native UFS speed; Android reset/OTA never touch an unknown partition. Risks in §3. |
| b | Loop image inside Android `/data` | **Impossible** | Whole partition is f2fs under dm-default-key with a *hardware-wrapped* key from the Tensor security block; file contents/names additionally FBE. Linux cannot read it; no root = no Android-side helper. |
| c | Existing spare partitions | **No (pending diag)** | I could not obtain the real cheetah table. Unused slot-B images (boot_b, vendor_boot_b, vendor_kernel_boot_b, init_boot_b, dtbo_b, vbmeta*_b, modem_b) total well under 1 GB [I]; they are exactly what OTA overwrites. `persist/efs/modem_userdata/metadata` are Android/radio-critical. |
| d | Free space in `super` | **Unsafe** | `super` is unslotted; Virtual A/B uses it for both slots/snapshots; every OTA rewrites the LP metadata from the payload, dropping any extra logical partition [I]. |
| e | USB-C SSD | Safe but poor | Needs host mode + VBUS boost (MAX77759 GPIO5/EXTBST, `USB-C-PLAN.md` B4c = design only [D]); only USB 2.0 until SS lanes work (~40 MB/s vs UFS >1 GB/s) → violates "fast/smooth"; bus power of NVMe enclosures likely needs a powered hub [I]. Keep as later backup. |
| f | Ubuntu inside Android's "Linux Terminal" (AVF Debian VM, Android 16 QPR1, Pixel 7 Pro supported) | Different product | Unrooted, OTA-safe, but not native Phosh/modem/GPU; mention only as a fallback. |

## 3. Option (a) — concrete plan
Preconditions: run the diagnostic (§6) first; need `sgdisk` (static arm64 binary) available in a RAM-only maintenance environment.

Sizing: 128 GB model ≈ 110 GB userdata, 256 GB ≈ 220 GB [S: user reports]. Suggested: `ubuntu` = 50 GB, Android `userdata` = the rest. Android OTA needs several GB free in /data (Virtual A/B COW lives there [S]) so never shrink Android below ~40 GB.

Steps:
1. **Backup Ubuntu** (4.1 GB used): `ssh ... 'tar -C / --one-file-system --numeric-owner -cpf - .' | zstd > ~/ubuntu-backup.tar.zst` on the Mac, plus copy of boot images (already in `out-ubuntu`). Also save `devinfo` dump and `sgdisk --backup` of LUN0 (to the Mac) **before** any change.
2. **Maintenance mode**: a RAM-only initramfs entry (e.g. cmdline `omamobile.maint=1`) that does not mount anything and temporarily lifts the storage guard for `sda` only. (Guard today: allowlist `boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata`, `/dev/sda` removed, mode 0000 [D] → needs a code change; that's intentional safety, do it as an explicit opt-in flag.)
3. In maintenance mode: copy the Ubuntu tar from the Mac into RAM disk? (no: 4 GB) → stream it later directly into the new fs instead.
4. `sgdisk`: delete `userdata`; recreate `userdata` at the **same start LBA** with the smaller end; create `ubuntu` after it (type GUID Linux filesystem, name `ubuntu`); use `--resize-table` only if table is full (can collide with first partition — check `Partition table holds up to N entries` first). Re-read with `partprobe`/`blockdev --rereadpt`.
5. `mkfs.ext4 -L omamobile-root /dev/disk/by-partlabel/ubuntu`; stream-restore the tar from the Mac (`ssh mac cat tar | zstd -d | tar -x`); `dd`/`blkdiscard` first 16 MiB of the new `userdata` so it is "wiped".
6. Patch initramfs `boot_arch()` (`PARTNAME=userdata` → `ubuntu`) and the guard allowlist (`userdata` → `ubuntu`), rebuild boot_b; flash from Mac. Keep a fallback: if `ubuntu` is not found, try `userdata` (old layout).
7. Boot Ubuntu to confirm. Then `switch-slot` to Android: expected first boot = auto-format (or one reset prompt). Android is stock+unrooted throughout.

Data-loss: Android data already gone (one-time). Ubuntu data preserved via tar + restore. Android reset never touches `ubuntu`.

Brick risk / recovery:
* A bad GPT does not touch bootloader LUs (LUN1/2: BL1/BL2/ABL) → BootROM→ABL→fastboot should still come up [I]. ABL then can't resolve partition names, so recovery = `fastboot flash partition:0..3` / full `flash-all.sh` from the factory image, which rewrites the stock GPT (seen in Pixel 7 flash logs: "Flashing partition:0..3" on `flash bootloader` [S/D]). Data in `ubuntu` stays on flash but its table entry disappears.
* **Any factory flash / bootloader flash resets our GPT.** Keep `sgdisk --backup` + a script that re-adds only the `ubuntu` entry (same GUID/start/end, no data touched). No reports found for Pixel 6/7 repartitioning [U]; precedents on other UFS phones (OnePlus 6, Xiaomi nabu) and older Pixels use `sgdisk`/`parted` from custom recovery [S: search results].
* Unknown: whether a monthly Android **OTA** rewrites `partition:0..3` (factory flash does; OTA path unverified) [U]. If it did, the same re-add script fixes it.

## 4. OTA interaction (applies to every option)
* Virtual A/B: non-dynamic partitions (boot, init_boot, vendor_boot, vendor_kernel_boot, dtbo, vbmeta*, bootloader, modem) are written **directly** to the inactive slot; dynamic ones go to COW on `/data` [S].
* Inactive slot = our slot B ⇒ OTA overwrites Ubuntu's boot images, marks B bootable, flips active to B ⇒ phone boots Android from B. Android stays on B; A now holds the old Android. Rootfs untouched (it is on `ubuntu`, not in `super`).
* Mitigations (pick one):
  1. **Don't install OTAs** while using Ubuntu (turn off auto-download, Developer options → auto system updates). Easiest; stale security patches.
  2. **Slot-agnostic Ubuntu**: after an OTA, re-flash the 5 boot images into whichever slot is *inactive* (`fastboot flash boot_a …` etc.) and set that slot active. Requires: initramfs guard allowlist derived from the *current* slot suffix (`androidboot.slot_suffix`) instead of hardcoded `_b`; `switch-slot`/`omamobile-bootctl` already operate on both slots [D]. ~1 min per OTA from the Mac. Boot images are unsigned; an unlocked bootloader boots them [D].
* Note update_engine marks the target slot unbootable at start of OTA → our slot shows "unbootable" in devinfo until the OTA finishes [I].

## 5. Recommendation
1. Run the read-only diagnostic (§6) and send me the output. Decide sizes.
2. If the GPT has free entries and `userdata` is the last partition: do option (a) in one go with the Android reset (Phase 1: backup; Phase 2: maintenance initramfs + sgdisk; Phase 3: restore; Phase 4: Android first boot).
3. Treat OTA as "reflash boot images after OTA" (mitigation 2) or hold OTAs (mitigation 1).
4. Keep slot-B-plus-userdata design as fallback until (a) is proven on this unit; (e) later.
Confidence: why-wipe analysis high (primary sources); (a) feasible medium-low (Tensor unproven, partition table limits unknown); OTA analysis medium-high.

## 6. First read-only diagnostic (prints cmdline slot/root, every LUN's partition name/start/size, mount, and which tools exist)
See the appendix at the end (also saved as diag-gpt.txt, the remote part only).

## Sources
* gs201 fstab: android.googlesource.com/device/google/gs201 (`fstab.gs201.in`)
* fs_mgr.cpp: android.googlesource.com/platform/system/core/+/refs/tags/android-10.0.0_r1/fs_mgr/fs_mgr.cpp ; libcutils/partition_utils.cpp (`partition_wiped`)
* AOSP docs: source.android.com/docs/security/features/encryption/metadata; /devices/tech/ota/virtual_ab
* Linux Terminal on Pixel: androidauthority.com/install-linux-terminal-app-on-pixel-3558010/
* Pixel 7 Pro storage sizes: reddit r/GooglePixel "Pixel 7 Pro System Storage"; XDA cheetah thread (super.img ≈ 6.25 GB)
* Repartition precedents: postmarketOS wiki "Dual Booting" (403 — via search only), Project-Silicium, nabu/OnePlus 6 guides
* Project files: DUAL_BOOT_ANALYSIS.md, USB-C-PLAN.md, initramfs/init, gs101/gscommon BootControl sources in `src/`

## Appendix: the diagnostic one-liner (run from the Mac, zsh-safe)
ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'cat /proc/cmdline | tr " " "\n" | grep -E "slot_suffix|root"; for d in /sys/block/sd?; do n=${d##*/}; echo "== $n size=$(( $(cat $d/size) / 2048 ))MiB lbs=$(cat $d/queue/logical_block_size) ro=$(cat $d/ro)"; for p in $d/$n[0-9]*; do [ -e $p/start ] && printf "%s name=%s start=%s sizeMiB=%s ro=%s\n" ${p##*/} $(sed -n s/^PARTNAME=//p $p/uevent) $(cat $p/start) $(( $(cat $p/size) / 2048 )) $(cat $p/ro); done; done; findmnt -no SOURCE,FSTYPE,SIZE,USED /; ls -l /dev/sda 2>&1; which sgdisk sfdisk parted lsblk'
