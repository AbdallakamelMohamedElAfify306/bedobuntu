# Root-hide fix kit — Pixel 7 Pro / Magisk 31.1

## What this does
Diagnoses why banking/payment apps refuse to open on a rooted Pixel, then applies
the late-2026 Magisk 31.x hiding stack that still works without a stolen keybox:

1. Enable **Zygisk**
2. Install **Zygisk-Assistant v2.1.4** (active hide)
3. Keep target apps on Magisk **DenyList** but leave **Enforce DenyList OFF**
   (required so Zygisk-Assistant can inject; plain Enforce-ON was already tried)
4. Add all processes for: HSBC, NBE, Ana Vodafone, Instapay, Payoneer, PayPal
   (+ Play Store). Does **not** add `com.google.android.gms` (Play Integrity Fork
   must keep injecting there).
5. Install idempotent `service.d/99-props-spoof.sh` (`verifiedbootstate=green`,
   `flash.locked=1`, `vbmeta.device_state=locked`, `release-keys`, etc.)
6. Refresh Play Integrity Fork fingerprint via `autopif4.sh` + `killpi.sh`
7. Clear data of the six apps + Play Store; trim DroidGuard cache
8. Leave `/data/adb/service.d/shared-part.sh` untouched
9. Does **not** flash, wipe, touch Ubuntu slot b, uninstall user apps, or disable adb

## Honest limits
- Unlocked bootloader cannot reliably pass Play Integrity **DEVICE** / **STRONG**
  on Android 13+. BASIC is the realistic target.
- HSBC / NBE / Instapay may still refuse if they demand hardware attestation or
  simply detect Developer options / USB debugging.
- Magisk 31.1 removed **Hide the Magisk app**. Uninstall Magisk Manager from
  Settings after setup; root and modules keep working.
- SwitchToUbuntu.apk can be a package-enumeration signal. This kit does not
  uninstall it. You may `pm disable-user` it later if needed.

## Layout
- `fix-all.sh` — Mac driver (`fix` / `diagnose` / `verify` / `reboot`)
- `phone/*.sh` — run on device via `su`
- `assets/Zygisk-Assistant-v2.1.4.zip`
- Logs: `$HOME/cheetah-dual/roothide-logs/`
