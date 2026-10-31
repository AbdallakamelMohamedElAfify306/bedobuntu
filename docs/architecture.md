# Architecture

```mermaid
flowchart LR
  subgraph phone [Pixel 7 Pro]
    A[Slot A Android]
    B[Slot B Linux boot images]
    U[Ubuntu root on userdata or ubuntu partition]
    S[Optional shared ext4]
  end
  A -->|SwitchToUbuntu app / bootctl| B
  B -->|Phosh reboot-to-Android GUI| A
  U --- S
  A --- S
```

- Bootloader stays unlocked. AVB is orange / unrestricted for unsigned slot-B images.
- Flash allowlist (boot scripts): `boot_b`, `init_boot_b`, `vendor_boot_b`,
  `vendor_kernel_boot_b`, `dtbo_b`, `userdata` only.
- Shared partition tooling finds partitions by GPT **name** (`userdata`, `ubuntu`,
  `shared`) and refuses to format Android/Ubuntu roots. Sector numbers in older
  notes are **examples** for one cheetah layout — always verify on your device.
- USB SSH: nftables allowlist form (accept ssh on `usb0`/`lo`, drop ssh elsewhere).
