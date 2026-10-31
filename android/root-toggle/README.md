# Root Toggle kit — Pixel 7 Pro (cheetah) / Magisk 31.1

Temporary **remove root** and **restore root** for banking apps, without touching
the bootloader, Ubuntu (slot b), shared partition sda33, or userdata.

## Honest limits (read this)

1. **Unroot is fully on-phone** (home-screen icon). It flashes the stock
   `init_boot_a` from a saved image, then reboots. Magisk is gone until re-root.
2. **Re-root after a real unroot+reboot CANNOT be done fully on-phone.**
   Without Magisk in the boot image there is no `su`, so nothing on the phone
   can rewrite `init_boot_a`. Re-root needs the Mac once:
   `bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh` (fastboot flash patched image).
3. **Bootloader stays unlocked.** Many Egyptian banks (HSBC, NBE, Instapay,
   Ana Vodafone) and PayPal check hardware attestation / unlocked bootloader.
   Removing Magisk helps apps that only look for root. It does **not** fake a
   locked bootloader. Expect some of the five to still refuse.
4. Never run `fastboot flashing lock`. That can brick this dual-boot phone.
5. SwitchToUbuntu needs root. In Bank Mode you cannot switch to Ubuntu until
   you re-root.

## What you get

- `android/RootToggle.apk` — three home icons:
  - **وضع البنك** — hard unroot (stock init_boot_a + reboot)
  - **وضع الروت** — on-phone re-root only if `su` still works; otherwise shows
    the Mac command
  - **Root Toggle** — menu (unroot / reroot / status)
- `phone/*.sh` — scripts installed to `/data/adb/roottoggle/` and
  `/sdcard/roottoggle/`
- `mac/setup.sh` — one-time: push stock + dump patched + install scripts + APK
- `mac/reroot.sh` — Mac fastboot re-root
- `mac/unroot.sh` — optional Mac trigger for the same unroot script
- Soft hide/show scripts (fully on-phone, both directions) — already proven
  insufficient for the five failing apps; kept as optional

## One-time setup (Mac, phone on Android, USB debugging on)

```
bash $HOME/cheetah-dual/root-toggle/mac/setup.sh
```

Needs `$HOME/cheetah-dual/root/init_boot_stock.img` (exact build). Setup also dumps the
current patched `init_boot_a` to `$HOME/cheetah-dual/root-toggle-images/` and to the
phone sdcard.

Then on the phone: Magisk → Superuser → enable **Root Toggle** / **وضع البنك**.

## Daily use

- Banking: tap **وضع البنك** → confirm → phone reboots without Magisk.
- Back to root: cable + `bash $HOME/cheetah-dual/root-toggle/mac/reroot.sh`.

## Safety

- Writes **only** `/dev/block/by-name/init_boot_a`.
- Refuses to run if slot is not `_a`.
- Does not touch `init_boot_b`, boot_b, sda31/32/33, vbmeta, or the bootloader.
- Does not delete `/data/adb` (modules preserved for when Magisk returns).
- Complete Magisk Uninstall is NOT used (that would wipe modules/service.d).

## Soft mode (optional)

```
adb shell su -c "sh /data/adb/roottoggle/soft-hide.sh"
adb reboot
# later:
adb shell su -c "sh /data/adb/roottoggle/soft-show.sh"
adb reboot
```

Does not remove Magisk from boot. Will not satisfy strong bank checks.
