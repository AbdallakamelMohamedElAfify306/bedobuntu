# Split plan: Ubuntu keeps its ext4 in place, Android gets a new userdata, 20 GiB stays free
Date 2026-10-29. Nothing here was run on the phone. Tested on this box: init patch (dash -n + fake-sysfs harness), repack identical-to-flashed
check, split-gpt.sh against a synthetic 121860 MiB GPT using the real start/size numbers (plan, backup, apply, wipe, raw restore all OK).

## 0. What changes (and one correction)
* The initramfs lives in **vendor_kernel_boot_b**, not boot_b. boot_b (the kernel) is unchanged, so only `vendor_kernel_boot_b` is flashed.
* New initramfs: root = the ext4 labelled `omamobile-root` on a partition named `ubuntu` or `userdata` (ubuntu wins); allowlist = old list + `ubuntu`.
  When the root is on `ubuntu`, Android's `userdata` is forced read-only in Linux. Works before and after the split. Falls back to the initramfs shell (SSH up) if no root is found.
* Layout (4096-byte LBAs, from your sysfs numbers: userdata = LBA 2383334..31196133):

| # | name | start LBA | end LBA | size | note |
|---|------|-----------|---------|------|------|
| 31 | userdata (Android, NEW) | 14704128 | 25953023 | 43941 MiB (42.9 GiB) | same index, same type GUID / unique GUID / attributes as today's entry 31 |
| 32 | ubuntu | 2383334 (unchanged) | 14704101 | 48128 MiB (47 GiB) | the existing ext4, ≥128 MiB bigger than the fs (47683 MiB) |
| - | unallocated | 25953024 | 31196133 | 20480 MiB | |
Index reasoning: Android finds userdata by name (fstab: /dev/block/platform/14700000.ufs/by-name/userdata, no length= field; recovery.wipe lists by-name/userdata and by-name/metadata only; ueventd by-name links come from PARTNAME). Index does not matter, so Android's userdata stays 31 (closest to stock), ubuntu is new index 32.
Android's userdata size is 43941 MiB; ext4 can't give more without shrinking it first (resize2fs). Change with --ubuntu-mib N / --free-mib N.

Define once in the Mac terminal (zsh):
```
ph() { ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 "$@"; }
```

## PHASE A — new initramfs first (old layout; nothing else changes)
**A0 (Mac, files).** Put the bundle (split-bundle.tar, 15 MB; sha256 of each file below) in $HOME/cheetah-dual/split:
`mkdir -p $HOME/cheetah-dual/split && tar -xf split-bundle.tar -C $HOME/cheetah-dual/split && cd $HOME/cheetah-dual/split && shasum -a 256 -c SHA256SUMS`
Expect 5 lines "OK". STOP on any FAILED.
Also confirm the full backup is where you said: `ls -l $HOME/cheetah-dual/backup/ubuntu-rootfs-20261029.tar.gz` (1.6G). STOP if absent.

**A1 (read-only) the flashed image on the phone equals the original (so rollback is meaningful).**
`ph 'for s in /sys/block/sd*/sd*; do grep -qx PARTNAME=vendor_kernel_boot_b $s/uevent && { n=${s##*/}; echo $n; head -c 7489536 /dev/$n | sha256sum; }; done'`
Expect: sdaNN then `948960a649b1ad8ba2c40c99a28698e3c414292e063dbbcf42175444a2dc0882  -`. If the hash differs: do not continue; send me the output (your phone runs a different image than out-ubuntu/images).

**A2 flash.** `ph 'sync; reboot-to bootloader'` (the ssh session drops)
then on the Mac: `fastboot getvar current-slot 2>&1 | head -1; fastboot getvar unlocked 2>&1 | head -1` → `current-slot: b`, `unlocked: yes`. STOP if current-slot is not b.
`fastboot flash vendor_kernel_boot_b $HOME/cheetah-dual/split/vendor_kernel_boot.split.img` → "Sending ... OKAY / Writing ... OKAY / Finished".
`fastboot reboot`  (do NOT set-active; b stays active)
Writes only vendor_kernel_boot_b (7.1 MB of a 64 MiB partition).

**A3 confirm (wait 60-120 s for ssh).**
`ph 'findmnt -no SOURCE /; dmesg | grep -E "omamobile: (ufs-ro: allowlist|arch: root)"'`
Expect: `/dev/sda31` and
`omamobile: ufs-ro: allowlist: boot_b init_boot_b vendor_boot_b vendor_kernel_boot_b dtbo_b userdata ubuntu`, `omamobile: arch: root is /dev/sda31 (userdata)`.
STOP/rollback (R1) if: ssh never comes back in 3 min, or "arch: root is" line is missing.

## PHASE B — split the GPT from the running Ubuntu (only after A3 is green)
**B1 install gdisk (sgdisk).** Online: `ph 'apt-get install -y gdisk 2>&1 | tail -2; sgdisk --version'`
Offline (no internet on phone): `ph 'cat > /root/libpopt0.deb' < $HOME/cheetah-dual/split/libpopt0_1.19+dfsg-1build1_arm64.deb; ph 'cat > /root/gdisk.deb' < $HOME/cheetah-dual/split/gdisk_1.0.10-1build1_arm64.deb; ph 'dpkg -i /root/libpopt0.deb /root/gdisk.deb 2>&1 | tail -3; sgdisk --version'`
Expect `GPT fdisk (sgdisk) version 1.0.10`. STOP if missing.

**B2 install the tool and print the plan (read-only; does a sgdisk --pretend rehearsal).**
`ph 'echo H4sICPSM4moCA3NwbGl0LWdwdC5zaAC9Wm1T20gS/u5f0VHMIhGEMeGSrB3nzgTIUhcMa+PdS0E2K9tjrMKWHEmGsAn32+/pHo1ebEhSqbvzVha9zHT39OvTM3r8qDbwg9rAiyeVxxTPp37iXs6TBg296FpRf7AIksV6TNEiCPzgkqIwTChc4N+YkomicRQGcvPnIlbRyEu8P8mOvZmiOPGihGI1TMJok4KQhuH81iEvGNGlf63ArR2MotAfkUedg9+LBAZq4mOYn2zSVHnXzPewe3Dw4fhojxaBN52GQy9RmJiIDApjU3FGfny1BdKUL2UrntB86gV0/y9S3sgNg+ltg+aRH2iKMp4ljdREeVGsIAvd+MmE4ktmQa47j1QCxqu8Bt7wajGn8/2j7vuHeb05PTMj7ZTmE4q8G3q71475UsXQmwJBhyBVSCC3ysubz6e3lPI6d91bFRuev3ePzg56shrmZQdKjWK51Wyb5MVXMd2GCwL15HauqHf69ujMWeVy48+V66XGKv/+UlGo/cCP4oR26djfM7Zgoxqbku2NExVpgTdh4DEWh0UO4E7M8WSe+GEQN6DYhbicO/MH1CF7pMbeYgrKL+o7LxzC+3Gk1PLbne3dF9vyduYHRtTVQfgJM1hAmxke6jNjSrzBFEaO6SbyE9i1yQ6bvYb/yyLwPgkXwwlcT30aqrl2Fr1o1gSeD25L6toEu5uJP5zQ1Fcx1n0bwquWnNbElvqU7JIN8sMrNXK2KrFKyFULCAKKY8+fVvaPev9sVT/zn4ZbG6nrWjzy7prUe5O+0RcNV7vUXaW/1+eoaYn6mlkUtURhTTo+6nxod/bTR/hVhrMRyNQbLocAKMcTf5zQly+URAsF/t2WZTXp3UGvtV3BwqC0c6o+JvcyoW1636QR4txDvFTrcNsKlezpkBGnumMo7zSbBZs6uYTLQ5YM65RkLw0WrogER8Ssp29AZMPhKGpVC49U7A1Z6EBVRr6yHfpMajgJyeqdnZw2qLph0aufQFx9QgLAvLvKOVlVG3HgLhyLWrxo1s45uQFefJYQ+oDAO2u4d5Z+B8JkwcYIOEmfVmUYzmacXdxrzNEmAx+xZ7CYTrNJaWIIkHL9APl0OoWH2d4ckamyRySDNimMkGxVlr4cq+KPIdcjuBC4aB7v6aef6Dy7bZHxITYdZrLFZldBOMpfDHi9SUQNWsd/L6kW38a1ATLwFb/mYdADqGq12ZFyh0hznJ1ZkowMaCqINPahwJJAZq3yQJY6DhfBKJXeHazKbgt3EIaZoQckoHQIBHnU0m7IaynSReRmyZdWCLTqDpwaslVOW1U7tQi584z3zquf6s6yWfCeg1KN4CenVqXXw1ytBdzSF1hjxF6xHtf+6EkVpNj/S5E9DS/9oTc9/6PxfsNp0MaFfb7t/vx+48LZ2qhd1GvzdUxG2cHsulPpHHTOHiZ8upTBJuEUWR5FBTk9p4tkk0TIP4a+Uzk86va+QvZQsvkiFpq6hLMKc4oozN7XR+S83rb/D6x2hNXZyVn77cO89tlsovdGUTuaZkE7aTT3epnXyT2bovxE1Fh+xKstPxGhiq4+9AL287kAi8yZrEpR6stIzcn96NP6PAqx8NnFl2EYRYt5cvHFD669qT+6+BJeq2jqwV/ArOiZmBtGSQxglU7W2IUDcriIIngDY4LGRcB+2z35fdlzvZsrWkcG/zfV/hAtPanWmEfn8FXrOfQjoWlVUSs4h6QwJs8gkmRRpLqoUZzwasARrh7lVm1UUkVP1t6tzdZG7tova8drPQeFZnY18iMTc10LZLI4TOe25E1NQIms08riM8+dmDcCchy3zKtwnM4Dupt50e0WQJZFg7il7TtEsklamSWRUZNF3Aq4IBB1UFlsW+xHLtXxj63rOM2HeGhBl1jEV/6c6fBcILu642RcO3vLLHMzvKJsva4g063kU8J6AfbNXuYw0aKXL7GEymMN6AXOd/VbDftOukdvjjpYyTLqEd9AyfADXpZ9E0bAhbjhSX7gJ5E3G8fOFkfgpWqgdBbAKUPP3j/fV/ZbF4IaCphkOCLrAub2o4DbAVxvc4ZGEOhiWokn3s7fnsWLGblD6v3Sxk2vf9wrjNBaLhiONX1R3WfdQrWpGrXtcBNcQ4vAKcFQAkIm5xZZmotaeXWvVWCUFVrxrf6rrbOswFQdo2YKaBFTMAQByo1SbxYa2XJzD6bi2gqivirqA3PZ5PkTJ/OTwnReiyhio9fDWga3iYo3CzT5fWev8LJpAhemNiEnet+ucJkux3ipBcgj/TEVYH0jR/t+nHUAdtrlObnfNUljQhkDt5eqxQA4mfgaIoF0v5MnJU5ReV563mpZhpP1WTdt1frdOsKyv/fVScK1NAWM0izd3ytn7X6nmLLRDejZT7I1zj0/apDgOunCpANiJfb3ekUU4afETbK4p/rpAnQvFOBF7a/S6/wwPQiokdVf9+HVzLJE3ZOTsw+97mvwHqMbn0FlLtTQO+l3Xx9QDYLtH+HdaDGbq51xTO5ElK4nMWTKcnKOnLLB2cAUQlnCUtBdar79o5WlTRWwZ4Jqdh1OF0gpnFewyBovi500nHmzcIBhruxS5NarsUNyyRWHK4/ipktzP+x92HsHVXCk0MNy7DF41LnCMKeNb45n6JcN5wqipij+OUttCHMvYJT1AVFgftCXuAValSd7+gnSlpmAy2e7G3V0dX97/gwjC56rbvK4lD0ZbmLRpU1DCJDo7l06T3SkTdES98AIR2tZAlqjnEPW+giXMgehUpe2GEDlMtD2PTk8bBWp1XJqWdUWn5FNhTAvr8jY9WOdsK0qqJiqvVvK05tjydLlclqu0ykhrsdLhAqzYL3hDNiLXtoahA9pt/7z7tPtXcqkc/JisLTxYfa08o2PFLFWsW6HvEjJTkEh2cLSP5LqirHSyRHjkLYkFuolF5ANC2+YIE3xCvMCxiGUC5tB0Adz53oOTWkrg53eKkWd4L0pd123vNQYfmebe9le+jv6wWMpS0/qEhGrvNEgz1rVYwajrdbsfuYF1ovZAMUI4xHuhhXWBu9jbR1b5E5VAccXkjtvQEiXdGuQD2+a6fJu66ZKpkHko+VknOdiNCDvTg9yYx492K296R/tw/lGKkvSbffQc8duOVf3edz30FsE/seFErJfp3jSO2t3zx4m+T0F6eSg8xWh3nrfqkDts7Puw/PbCXrVwQJNwnjqXcZLyylTMh0WtL5UvVkT5Ud65UvPsJJvdmY+TA9Pbf+rtOxSiHz2x3b16ZPtVzMH/oqLO4xN43V2J4IaZi32RKFl3Zc/bWRh+BqPdYpVS3rg3NVtuddjNTV4Zvvt0RtOJXaaV5FhuWw0dRY3D9d0LSnn7xCJMi5sUnDjUkEH4bpuaYtSSuZsAd4DlVcOhIxZwKZsm8uIsZ+YYOIi9KfOCX8yzXRzJ3gYgnylNGbABCA2qXAdrXwbrVQ0usjxCdtBNlLvqgbpPYh3y0AC6s/obEIBc+gN7ptRI9sow7GkG/6voqT/FUbKeaVeN/UGSjYcy1NYhv8nUuL62P/QO3h9JuBBbyCDzLKPY4zObDrO+YGOVzt9A4ik6XArD7ptMwFrsGUwt4H4J2Ekg0Bc32ykf2VaSpbsEzPHzY+nlgRbocDbCEJFtq2ZihDE83YmZt1ZAkgCGIVF90D2twxzniWZYmW8ZBxjJ134eFqqARkOUXZebORTCs6gozrmKYbGq1c72xgDmJO1b3bVmANPnSwtoFedKk5PIC+waOpFlyrSRVjkteS8gG/KOZmfgJwlQBdpMt/hL+bKFYh1Ey6mI+Ysu7uahjC2Z9zbFsg4ZSEEDZgakErQN++WBDTcB4CEU+82XHCbD2twYjIeYTxtGZzDHJV4Et584I15OWTghv7ly9O37U5FiozghwbpvUKzIcl4krcq0l6eEUkBiphN3U2zNar3Qba2ZAuyUuzF87pR7TQy6mmkYIL4kp25latfAJVt9Hq1goOwmTf1WaHUXCR7FGtQ4opeydqpUoZs3O9EFa1DA49jJztS1B1E+uNTMv3jOQT5qQCtU0/Y5I0GEDDmkitekvEFulJqHovgtQJSqmnp01M4aDYjzZyOyfg52bIxwUtLxaz2M079lJMJhVR+NCQTL7hUEE5Ow3VtTE/B5YSKSkfZCRJ8pgJoTBbAuNiYh/5dzTKAKEOc564SX35QIz8Rr3osGDrd70vhC2IPdSBg9B3qQ1ZpQuZROFQxJ18p0VzWopGKuE6ySFPyWrbrcW4baYird8AbRseNLIgS/VxjMHeh71L8hXaEb7P+wpRh9hd9WLP003HoPQHztkxtNbY/6eE8V16wIMcNY4JGFrGJPN8+fP3s6X770H2x++Kpu/v8+Y774uD5z+7T/Wc/77/A/f7BbirYcSPtapBdBauNaX0tvgjWGRp45/94f2dBweYTANYwH4958zEfe4Jdu/umRy/RJ6Y2YAl/LXYHp0yIRwmthw+U0m8JZDMpPVK6CKq/cqn9WDiTxJO8YFrVusXnkURjgLa5J1jrx4+E/qvHPiTHMT9y8sVnsflW0Ef8DyuzHA3X7jvWyQbkGZq7drSBafwZCFrUsc2TnC3qIGHJ5h2g7ZaVngMDSz6wi4huNGghA6EbfdQKsnZ8s7qzWX26WX0ufXm3nU/+dXlmoZ+9/3CFL4S6uZjdy8ag2T2tmG67uP4Qy43ynB+n9VHr4x51LOshP4W4T/64laVZ3KlWmmqlQ9dS77RasVw8bbWUXJS3Mcat+h1xfyQbII/Gd+urbVAU3tBNFKLjgLxGVtSL+SJ5QD7Rq5avX5Kvn8s3+5p86ebw16TT5eC7ZCu62wkqu3ZKFMzplFYM5I8QjRwZGbRKN+rSD5x67eMDyvaRUkyC1KS/tEDLwt9ayKE/ZTBD76c0sy+YzP6KDWw/4Vbuxsu+dnGsZrMiDuCUj++q9jTmCrByjLdR7FxgBClfbp0P8tK+To49TK8dp8dV+RnG8rcR69Xt9DxiPd9Jf+gABdnbdT8ufFU6FSlAtOK5BqJa6Y5m5iXDCfnQq3xjA0qxJYcY+VdRGsSOVDyM/LTDfd3vdhluSTa9b0vxWweJ2YbiPeeQWcvHpdpkrNgPhqr0qVbiXQFXSxsNgiz0g3Y2+/tW9R0D/0eyFZj21KbInXG9L3wgtnygBUS0Fm/RnnBvENfEs+wDMa4jwxD+GiwUfxRiNKEN1ZTvLMiNyNN7lB6nKD0xs/jQwwK5t0z3ub9RU009LRXT7Pij/FGGLp9NcyYnh5tyZrl8XMo6vA2G+PNbsWRfl0q0+fAp3538zcq8fTdPRL8VjuxpvROac/dYf8yyvvLpyHV2Rm9Gfp/I93ybUhRHqmZpc/L4hw+KdGnpr3ZAaYrKwkoDXqQqM/jRdy1Fq46bmjQLbdEZfPFKRYGaGsTO59Zv981BtXxvJnswM442/vJGckdxt2YdUfIp2dQOr89jtzi9bTjZ8nc26ztzdtxtK/2yi78a40/BKv8Bg+S8lA8rAAA= | base64 -d | gzip -dc > /usr/local/sbin/split-gpt && chmod 755 /usr/local/sbin/split-gpt && sha256sum /usr/local/sbin/split-gpt'`
Expect sha256 `f8f71b6e490c47c214f18efc6a291e8651db96fcdfba87931516653f714770d4`.
`ph 'split-gpt plan'`  Expect (numbers must match; the first line shows your real GPT size/entries):
```
userdata is partition 31: sectors 2383334..31196133 (112550 MiB) ... root ext4 on /dev/sda31: 47683 MiB   (or similar, must be <= 48000)
  31  userdata (Android, NEW)  14704128  25953023  43941
  32  ubuntu  (this ext4)      2383334  14704101  48128
  --  unallocated tail         25953024..31196133  ~20480 MiB
pretend run OK: header, all other partitions identical; ubuntu starts at the SAME sector 2383334
(nothing was written)
```
STOP (script dies by itself) on: userdata not last / not the root's partition / ext4 bigger than 48000 MiB / "header changed" / "other partitions would change" / no free GPT entry. In that case send me the output; do not force.

**B3 backup the partition table, copy it to the Mac, verify.**
`ph 'split-gpt backup'` → prints 3 sha256 lines + "backup in /root/gpt-backup-YYYYmmdd-HHMMSS".
`ph 'tar -C /root -cf - $(cd /root; ls -d gpt-backup-* | tail -1)' > $HOME/cheetah-dual/backup/gpt-backup-20261029.tar && mkdir -p $HOME/cheetah-dual/backup/gpt && tar -xf $HOME/cheetah-dual/backup/gpt-backup-20261029.tar -C $HOME/cheetah-dual/backup/gpt && (cd $HOME/cheetah-dual/backup/gpt/gpt-backup-* && shasum -a 256 -c SHA256SUMS)`
Expect `gpt.sgdisk: OK`, `primary.raw: OK`, `backup.raw: OK`. STOP if not 3 OK. (restore.sh in that dir restores with plain dd.)

**B4 THE write (point of no return only in the sense of the table; recoverable with B3).** Stops udevd first so it cannot re-probe mid-write (it comes back at reboot).
`ph 'systemctl stop systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket; split-gpt apply --yes'`
Expect the same plan, "pretend run OK", sgdisk's "Warning: The kernel is still using the old partition table" (normal: / is mounted), "The operation has completed successfully.", `No problems found`, the 4 last table rows (31 userdata 14704128-25953023, 32 ubuntu 2383334-14704101) and `GPT written.`.
STOP if the output shows "STOP:" or "restore with": run R2 immediately; do not reboot.

**B5 make Android's new userdata look blank (so Android formats it itself).**
`ph 'split-gpt wipe-android'`  Expect: `first 4 MiB of Android userdata (sector 14704128) are zero`. (The tool refuses unless the region starts ≥64 MiB beyond the end of the running ext4.)

**B6 reboot and verify.** `ph 'sync; reboot'` (wait 60-120 s)
`ph 'findmnt -no SOURCE,SIZE /; for n in 31 32; do echo sda$n $(grep PARTNAME /sys/block/sda/sda$n/uevent) ro=$(cat /sys/block/sda/sda$n/ro); done; dmesg | grep -E "omamobile: arch: root"; sgdisk -p /dev/sda | tail -4'`
Expect: `/dev/sda32  ~45.8G`; `sda31 PARTNAME=userdata ro=1`; `sda32 PARTNAME=ubuntu ro=0`; `omamobile: arch: root is /dev/sda32 (ubuntu)`.
Data check: `ph 'ls /home /root | head; uptime'`. Your files are exactly as before (same blocks). STOP/R3 if the phone ends in the initramfs shell ("no omamobile-root file system").

**B7 (optional, cosmetic) keep Android's partition hidden from desktop tools** (not needed for safety: Linux holds it read-only).
`ph 'for f in /etc/udev/rules.d/10-omamobile-storage.rules /usr/lib/udev/rules.d/10-omamobile-storage.rules; do [ -f $f ] && sed -i /ID_PART_ENTRY_NAME/s/userdata/ubuntu/ $f && grep ID_PART_ENTRY_NAME $f; done'`
Expect one line ending udev ENV match for ubuntu (see script). Takes effect at next boot.

## PHASE C — Android once (optional, user's call)
1. `ph 'reboot-to bootloader'`, Mac: `fastboot getvar current-slot 2>&1 | head -1` (b); `fastboot --set-active=a`; `fastboot reboot`.
2. Expected: Android formats its new, zeroed userdata and boots to setup wizard (partition_wiped() is true, fstab has "formattable"; this auto-format path is from the AOSP source but unverified on this phone). If instead it shows "Can't load Android system": choose Factory data reset: recovery.wipe for gs201 lists only by-name/userdata and by-name/metadata, never `ubuntu`.
3. Before any Wi-Fi: Settings → System → Software updates → turn off automatic updates (OTA overwrites slot B boot images; see OTA note in coexist-study.md).
4. Back: reboot to bootloader (power+vol-down), `fastboot --set-active=b; fastboot reboot`. Ubuntu is untouched.
Note: scripts/to-android.sh and the "can erase Ubuntu data" wording in the launcher/switch-slot are now obsolete (no erasure); to-linux.sh refuses after Android booted (state file) — use fastboot --set-active=b or switch-slot.

## RECOVERY
* **R1 initramfs broken / won't find root (Phase A):** hold Power+Vol-Down → bootloader; `fastboot flash vendor_kernel_boot_b $HOME/cheetah-dual/split/vendor_kernel_boot.orig.img; fastboot reboot`. If ssh still works in the initramfs shell instead: `ssh ... 'sh'` then investigate; the userdata ext4 has not been touched in Phase A. If B retries run out ABL boots Android: it will show the recovery wipe prompt — DO NOT confirm while the layout is still old (userdata holds Ubuntu); power off and use the bootloader.
* **R2 GPT problem (B4/B5), phone still running Ubuntu:** `ph 'sh /root/gpt-backup-*/restore.sh'` then `ph 'sync; reboot'` (restores the original table byte-for-byte with dd; checks sha256 first). If Ubuntu no longer boots but the initramfs shell answers on ssh: `mknod /dev/sda b 8 0` if missing, push the backup: `ssh -i "$CHEETAH_SSH_KEY" root@172.16.42.1 'cat > /run/b.tar' < $HOME/cheetah-dual/backup/gpt-backup-20261029.tar`, then `ssh ... 'tar -xf /run/b.tar -C /run && sh /run/gpt-backup-*/restore.sh'` (busybox dd/sha256sum only), then reboot.
* **R3 table fine but root not found:** no data moved. ssh into the initramfs shell; `dumpe2fs -h /dev/sda32 | head` should show label omamobile-root; reflash orig vendor_kernel_boot_b + restore.sh puts the old layout back (Ubuntu then boots as before).
* **R4 nothing boots / no fastboot:** hold Power+Vol-Down for bootloader (fastboot is in the bootloader LUs, which this plan never touches). Factory image flash-all.sh rewrites the stock GPT (userdata becomes whole again → Ubuntu's blocks are inside it and Android will format them). Last resort: re-install Ubuntu from $HOME/cheetah-dual/backup/ubuntu-rootfs-20261029.tar.gz.

## Risks / confidence
* Table edit on a live mounted disk: kernel keeps the old table until reboot (CONFIG_BLK_DEV_WRITE_MOUNTED=y in kernel-out/.config, so the whole-disk write is allowed). No partition data is written except the 4 MiB zeroed beyond the ext4 end.
* sgdisk writes the whole GPT (primary + backup, protective MBR). Pretend run + before/after comparison guard the rest of the table; unknown: Pixel's non-standard bits in the header (the script aborts on any change in entry count/usable range/other rows). A malformed table could stop ABL (bootloader LUs untouched, so fastboot remains) — Tensor repartition has no confirmed precedent in my search.
* Android auto-format of a zeroed userdata: source-confirmed logic, not seen on this phone (worst case one recovery tap).
* Any factory/bootloader fastboot flash (flash-all, `fastboot flash bootloader`) rewrites the stock GPT and drops the ubuntu entry (the data stays on flash). So right after B6 run `ph 'split-gpt backup'` again and copy that new-table backup to the Mac too: restore.sh from it brings the split layout back. (The tool refuses plan/apply once `ubuntu` exists; backup still works.)
* OTA: unchanged, see coexist-study.md section 4 (boot images of slot B get overwritten; rootfs survives).
Confidence: initramfs change high (tested logic, minimal diff, rollback = one fastboot flash); GPT edit medium-high (tested on a synthetic table with identical numbers; real Pixel GPT header unknown until B2 runs); Android first boot medium.

## Artifacts (box)
/workspace/split/artifacts/: vendor_kernel_boot.split.img f385ab2f…8d29 | vendor_kernel_boot.orig.img 948960a6…2882 | split-gpt.sh f8f71b6e…70d4 | gdisk/libpopt0 arm64 debs | SHA256SUMS; bundle /workspace/split/split-bundle.tar (15 MB). Source changes: build-ubuntu/{patch-init-split.py,repack-vkb.py,30-initramfs.sh}.
