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
- KPM: SukiSU-Nova KPM bridge enabled with CONFIG_KPM=y; KernelPatch 0.13.9 kpimg is injected into the final Image and verified with kptools
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

The build fails if `olddefconfig` drops `CONFIG_KPM=y`, `CONFIG_KALLSYMS=y`, or `CONFIG_KALLSYMS_ALL=y`, or if the SukiSU-Nova KPM bridge sources are absent. After compiling, the workflow injects the pinned KernelPatch 0.13.9 `kpimg` runtime into the final `Image`, checks the result with `kptools-linux -l`, and requires `patched=true`. `kpm-image-proof.txt` records the tool/payload hashes and exact final Image SHA-256; verification runs again before AnyKernel3 packaging. This confirms the expected build-time runtime injection, but the Manager's KPM status and module loading still need to be tested on the device after flashing.

## AnyKernel3 settings

The generated installer uses `do.devicecheck=1`, `do.modules=0`, `do.systemless=0`, `do.cleanup=1`, `do.cleanuponabort=0`, device names `sapphiren` and `sapphire`, Android versions `13-17`, and the requested `init_boot_a` split/flash versus boot dump/write flow.


## AVC Log Spoofing (experimental Linux 5.15 integration)

- Adds SukiSU-Nova feature ID `10003` (`avc_spoof`).
- Connects the Manager feature handler to SUSFS inline static key
  `susfs_is_avc_log_spoofing_enabled`.
- Uses the AVC-only changes from SukiSU-Nova PR #1058, pinned to head
  `119983f4dd8ca79dc69324cd358a73e104e35ab1` and base
  `4bec532dd447e2852aa8932afa768255350c103a`.
- The PR is open/unmerged and its author reports testing on Linux 5.4.
  This builder deliberately excludes its Linux <5.10 SELinux-hide compatibility
  changes; only the AVC handler and required registration changes are applied.
- The build verifies the handler source and emits `avc-spoof-build-proof.txt`.
  This is not proof of runtime behavior. Confirm the Manager reports
  **AVC Log Spoofing: Supported** after booting the resulting kernel.

The AnyKernel3 installer retains the requested device checks (`sapphiren`,
`sapphire`), Android 13–17 support, boot partition flow, and exact properties
from the supplied installer specification.
