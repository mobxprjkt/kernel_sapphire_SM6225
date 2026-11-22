# Sapphire Linux 5.15 — SukiSU-Nova + SUSFS + KPM

A minimal GitHub Actions kernel builder for Xiaomi Redmi Note 13 4G (Sapphire).

## Fixed build configuration

- Source: `https://github.com/The-Angel-Place-Sapphire/kernel_xiaomi_sapphire.git`
- Branch: `lineage-23.2`
- Defconfig: `vendor/sapphire_defconfig`
- Kernel series: Linux 5.15 (validated before build and after Image creation)
- Toolchain: Neutron Clang `06092026`
- Root: SukiSU-Nova (`builtin` branch)
- SUSFS: `gki-android13-5.15`
- KPM: enabled through SukiSU-Nova Kconfig
- Cache: ccache, 5 GB, persisted using GitHub Actions cache
- Output: kernel `Image` and device-configured AnyKernel3 ZIP

## Run

1. Upload/extract this project into the repository root.
2. Keep only `.github/workflows/build.yml` as the workflow file.
3. Open **Actions → Sapphire Kernel Build — SukiSU-Nova + SUSFS + KPM**.
4. Select **Run workflow** on the `stg` branch.
5. Download artifact `Sapphire-SukiSU-Nova-SUSFS-KPM` when successful.

The workflow is a single standalone `workflow_dispatch` file; it does not call a reusable workflow.

## Included features only

SukiSU-Nova, SUSFS, KPM, Neutron Clang, ccache, and AnyKernel3 packaging. Unrelated root systems, NTSYNC, Baseband Guard, NoMount, extra patch stacks, and optional feature workflows are not included.

## Important

This ZIP contains the builder scripts and one GitHub Actions workflow. The full kernel source is cloned by the workflow at build time; it is not bundled in this ZIP. SUSFS integration and the complete kernel build must still pass on GitHub Actions before the resulting ZIP can be considered tested or safe to flash. Always keep a known-good boot image available.
