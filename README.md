# Cheetah Dual (Ubuntu + Phosh for Pixel 7 Pro)

**Author:** Abdalla Kamel Mohamed El Afify  
**Version:** 0.1.0 (2026-10-31)  
**License:** GPL-3.0-or-later (see LICENSE); some files retain MIT notices from Omarchy Mobile.

Arabic overview: [README.ar.md](README.ar.md)

## What this is

Scripts and documentation to run **Ubuntu 24.04 (noble) with Phosh** on a
**Google Pixel 7 Pro (cheetah)**, next to stock Android, with:

- slot-B Linux boot images and a Ubuntu rootfs build pipeline
- two-way switch helpers (Android app icon + Phosh "Reboot to Android" GUI)
- an optional shared ext4 partition mounted on both OSes
- Ubuntu health / lock-screen / hardening helpers
- optional Magisk helper scripts for rooted Android (no third-party module zips)

## Honest prior-art claim

To our knowledge, this is the **first public Ubuntu + Phosh port for the Google
Pixel 7 Pro (cheetah)** that runs alongside Android with two-way switch icons and
a shared partition.

**Not claimed as new:** dual-boot next to Android on A/B slots (Omarchy Mobile's
own model) and slot-switch apps (seen on other devices). Kernel and device bring-up
owe a large debt to [Omarchy Mobile](https://github.com/derekross/omarchy-mobile)
(Arch Linux ARM + Hyprland, MIT). This project is Ubuntu + Phosh, not Omarchy.

## Authorship and credits

**Idea, design and integration: Abdalla Kamel Mohamed El Afify.** The idea of this
project and the specific combination below are his original work, and to his
knowledge nobody published them before:

- running **Ubuntu (noble) with Phosh** natively on the Pixel 7 Pro (cheetah),
  built on the Omarchy Mobile kernel and pipeline;
- keeping stock **Android on slot A** and **Ubuntu on slot B** side by side, kept separate;
- **two-way switch icons** (Android to Ubuntu and Ubuntu to Android);
- a **shared ext4 partition** readable and writable by both systems;
- the Ubuntu health, repair, hardening and lock-screen fixes for this device.

Built with the help of, and with thanks to:

- [Omarchy Mobile](https://github.com/derekross/omarchy-mobile) by Derek Ross
  (MIT): mainline kernel, device bring-up and build pipeline used as the base.
- Tools and guides from the [XDA Developers](https://xdaforums.com/) community
  for the Pixel 7 Pro (flashing, slots, AVB and boot images).
- [Magisk](https://github.com/topjohnwu/Magisk) by topjohnwu (GPL-3.0), used to
  root the Android side.
- Ubuntu (Canonical) and Phosh (GPL-3.0). This project is not affiliated with or
  endorsed by any of them.

## DISCLAIMER — read before you touch a phone

- These scripts can **brick** the device, erase userdata, or corrupt the GPT.
- An **unlocked bootloader** is required and must stay unlocked for this design.
- **Never** run partition or flash scripts without verifying your own layout and
  keeping verified backups.
- Slot-A Android system is treated as sacred; scripts refuse writes outside a
  hard allowlist. A shared-partition GPT edit is optional and separate.
- This project is **not affiliated with Canonical or Google**. "Ubuntu" is used
  descriptively for an Ubuntu-based rootfs.

## Repository layout

| Path | Contents |
|------|----------|
| `ubuntu/` | Rootfs / Mesa build pipeline (Ubuntu noble arm64 + Phosh) |
| `boot/` | Slot-B flash helpers, initramfs / image build, AVB fix notes |
| `shared-partition/` | Create / mount / rollback for the shared ext4 partition |
| `switch/` | Android Switch-to-Ubuntu app source + Linux reboot-to-Android GUI |
| `health/` | Ubuntu health checks, repair, hardening |
| `lockscreen/` | Phosh lock-screen / wallpaper CSS helpers |
| `android/` | Magisk helper scripts (root-hide, root-toggle, Shamiko, backup) |
| `docs/` | Install notes, architecture, prior art, offline validation |

## Quick start (high level)

1. Unlock the Pixel 7 Pro bootloader (factory reset). Keep Android on slot A.
2. Build or obtain slot-B boot images + Ubuntu userdata image (see `docs/` and
   `ubuntu/`, `boot/`). Set `CHEETAH_BUILD` to your build tree.
3. Flash **only** allowlisted slot-B partitions + userdata with
   `boot/scripts/flash-linux.sh` (reads SHA256SUMS; confirms interactively).
4. Optional: create the shared partition with `shared-partition/` after you verify
   GPT layout on **your** device.
5. Install switch helpers from `switch/`.
6. Publish: follow [PUBLISH.md](PUBLISH.md) for GitHub + Zenodo DOI.

Shell scripts are meant to be run as:

```
bash path/to/script.sh
```

(no shebang bang characters in this tree, by project convention).

## Environment variables used in docs and scripts

| Variable | Meaning |
|----------|---------|
| `CHEETAH_BUILD` | Root of your local kernel + omarchy-mobile + out tree |
| `CHEETAH_SSH_KEY` | Path to **your** SSH private key for USB networking |
| `CHEETAH_SSH_PUBKEY` | Path to a `.pub` file to embed at image build time |
| `CHEETAH_USER_PASSWORD` | Initial `user` account password (default placeholder `user`) |
| `CHEETAH_TZ` | Timezone for lock-screen helpers (default `UTC`) |
| `HOME/cheetah-dual` | Suggested local working directory on your computer |

USB networking defaults (generic): phone `172.16.42.1`, host `172.16.42.2/24`.

## Upstream and modules (not vendored)

Download yourself; do not commit binaries into this repo:

- Omarchy Mobile: https://github.com/derekross/omarchy-mobile
- Magisk: https://github.com/topjohnwu/Magisk
- PlayIntegrityFork, Zygisk-Assistant, Shamiko: use their upstream GitHub releases
  (names only in `android/` docs)

## License

GPL-3.0-or-later for original scripts unless a file says otherwise (SPDX headers).
Omarchy-derived helpers keep the MIT notice. Kernel work remains GPL-2.0.
See NOTICE and LICENSES/.

**DOI:** [10.5281/zenodo.23826278](https://doi.org/10.5281/zenodo.23826278)
