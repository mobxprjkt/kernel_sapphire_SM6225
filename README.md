# Sapphiren Kernel — SukiSU-Nova

Automated AIO kernel builder for **Redmi Note 13 4G / NFC** (`sapphire` / `sapphiren`), based on Android common GKI `android13-5.15`.

## Build

1. Open **Actions → Build Kernel — AIO**.
2. Select stable or testing, then run the workflow.
3. The workflow builds only the **SukiSU-Nova** variant, packages an AnyKernel3 ZIP, resolves the matching SukiSU-Nova Manager artifact when available, and publishes a GitHub Release.

## Device / installer

- Device codenames: `sapphire`, `sapphiren`
- Partition layout: A/B
- AnyKernel3 installer targets the active `boot` slot only.
- Manager APK is attached when the upstream SukiSU-Nova CI artifact is available.

> Flash at your own risk. Keep a backup of your boot image and ensure the ROM/kernel ABI is compatible before flashing.

## License

Unless noted otherwise, this repository is under GNU GPL v2 (see [LICENSE](LICENSE)).
