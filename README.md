# Sapphire Kernel — SukiSU-Nova + SUSFS + KPM

Minimal GitHub Actions build project for Redmi Note 13 4G/NFC (Sapphire/Sapphiren),
using Android 13 GKI Linux 5.15.

## Included features

- SukiSU-Nova
- SUSFS, using the `gki-android13-5.15` integration branch
- KPM (`CONFIG_KPM=y`)
- Neutron Clang toolchain
- ccache (5 GB GitHub Actions cache, restored between runs)
- AnyKernel3 flashable ZIP packaging

Other root solutions, optional kernel feature patches, extra governors, NTSYNC,
NoMount, Baseband Guard, manager APK builds, and unrelated workflows have been
removed from this build project.

## Kernel configuration

The build uses `arch/arm64/configs/vendor/deconfig_sapphire` as its defconfig.

## Build

1. Open **Actions**.
2. Select **Build Sapphire — SukiSU-Nova + SUSFS + KPM**.
3. Run workflow. The first build populates ccache; later builds can reuse cached compiler objects.
4. Download the `sapphire-sksu-susfs-kpm` artifact.
5. Flash the AnyKernel3 ZIP from recovery.

## Compatibility note

The SUSFS integration includes a Linux 5.15 compatibility adjustment:
`fsnotify_alloc_group()` is called with the one-argument API declared by this
kernel series. This project has not been compiled or boot-tested in this
environment; the next GitHub Actions run is required to validate the full
upstream SukiSU-Nova/SUSFS source combination.

## License

See [LICENSE](LICENSE).
