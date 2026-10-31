# Shamiko kit for Pixel 7 Pro (Magisk 31.1)

Shamiko is a Zygisk module that hides Magisk mounts, Zygisk, and related props from apps listed in Magisk DenyList. It is a stronger root hider than Magisk Enforce DenyList alone.

## What this kit does

1. Soft-disables Zygisk-Assistant (writes a `disable` file; does not delete it).
2. Installs official Shamiko v1.2.5 (414) from LSPosed GitHub releases.
3. Turns Enforce DenyList OFF (required; Shamiko uses the list as a hide list).
4. Adds HSBC, NBE, Ana Vodafone, Instapay, PayPal (all processes) to DenyList.
5. Clears those apps data so they re-check integrity after reboot.
6. Leaves PlayIntegrityFork / Magisk / Ubuntu slot / bootloader untouched.

## Requirements

- Phone on Android slot a, USB debugging on, Magisk su granted to Shell.
- Zygisk already ON (kit also forces zygisk=1 in Magisk DB).
- Mac with `adb` in PATH.

## One-liners

See `COMMANDS.txt`. Short version:

```
mkdir -p $HOME/cheetah-dual && cd $HOME/cheetah-dual && python3 -c "import zipfile; zipfile.ZipFile('$HOME/Downloads/shamiko-kit.zip').extractall()"
bash $HOME/cheetah-dual/shamiko-kit/mac/install.sh
adb reboot
bash $HOME/cheetah-dual/shamiko-kit/mac/install.sh verify
```

## Zygisk-Assistant vs Shamiko

Use only one active hider. This kit soft-disables Zygisk-Assistant and enables Shamiko. Do not re-enable both at the same time.

## Magisk Settings checklist (after reboot)

- Zygisk: ON
- Enforce DenyList: OFF
- Configure DenyList: bank apps with every process ticked
- Do not put `com.google.android.gms` on DenyList (PlayIntegrityFork must inject)

## Honest limits

Shamiko hides Magisk from DenyList apps. It does **not** spoof a locked bootloader or Strong Play Integrity. Apps that use hardware attestation (key attestation against the real locked state) can still refuse. Unlocked bootloader on this Pixel means DEVICE/STRONG integrity may still fail for the strictest banks (HSBC, NBE, Instapay are the usual hard cases). PayPal is more likely to improve. Ana Vodafone varies.

Developer options ON and Magisk Manager visible also trip many Egyptian banks. Turn Dev options OFF after adb work is finished.

## Safe mode if something boots wrong

Hold Volume Down during boot to enter Magisk Safe Mode (modules disabled). Then remove the `disable` flag from Zygisk-Assistant or add `disable` under `zygisk_shamiko` and reboot.

## Shamiko source

- Release: Shamiko 1.2.5 (414), 2025-06-18
- URL: https://github.com/LSPosed/LSPosed.github.io/releases/download/shamiko-414/Shamiko-v1.2.5-414-release.zip
- Module id: `zygisk_shamiko`
- Min Magisk: Canary 27005+ (Magisk 31.1 is fine)
