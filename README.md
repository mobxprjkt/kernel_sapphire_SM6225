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
- KPM: enabled through SukiSU-Nova Kconfig; final .config must retain CONFIG_KPM, CONFIG_KALLSYMS and CONFIG_KALLSYMS_ALL, with KPM source files present
- Cache: ccache, 5 GB, persisted using GitHub Actions cache
- Output: kernel `Image` and device-configured AnyKernel3 ZIP (device check sapphiren/sapphire; Android 13–17; boot install flow as requested)

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


## KPM validation

The build now fails if `olddefconfig` drops `CONFIG_KPM=y`, `CONFIG_KALLSYMS=y`, or `CONFIG_KALLSYMS_ALL=y`, or if the SukiSU-Nova KPM implementation sources are absent. `kpm-build-proof.txt` is uploaded with the artifact. This proves build configuration/source presence, not runtime KPM support by itself; after flashing, confirm the Manager reports KPM as Supported.

## AnyKernel3 settings

The generated installer uses `do.devicecheck=1`, `do.modules=0`, `do.systemless=0`, `do.cleanup=1`, `do.cleanuponabort=0`, device names `sapphiren` and `sapphire`, Android versions `13-17`, and the requested `init_boot_a` split/flash versus boot dump/write flow.
