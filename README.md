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
- KPM: SukiSU-Nova KPM bridge enabled with CONFIG_KPM=y; matching kpimg and kptools are built from the same pinned SukiSU-Nova KernelPatch source revision and injected into the final Image
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

The KPM pipeline checks more than `CONFIG_KPM=y`: it verifies the SukiSU-Nova bridge ABI v2, checks the KernelPatch-side supercall header for the same ABI and magic values, confirms `__arm64_sys_truncate` exists in the linked `vmlinux`, and builds both ARM64 `kpimg` and host `kptools` from the same pinned SukiSU-Nova KernelPatch commit (`1c5b608916357ac86a94cc736e235db1fac4a29d`). The resulting Image is patched and inspected with that matching `kptools`; `kpm-image-proof.txt` records source commit, binary hashes, and exact Image SHA-256. Verification runs again before AnyKernel3 packaging.

This is build-time ABI and payload validation, not proof of successful runtime module loading. Confirm the Manager reports **KPM: Supported** and test loading a known-good KPM after booting the resulting kernel. Keep a known-good boot image available.

## AnyKernel3 settings

The generated installer uses `do.devicecheck=1`, `do.modules=0`, `do.systemless=0`, `do.cleanup=1`, `do.cleanuponabort=0`, device names `sapphiren` and `sapphire`, Android versions `13-17`, and the requested `init_boot_a` split/flash versus boot dump/write flow.


## AVC Log Spoofing (experimental Linux 5.15 integration)

- Adds SukiSU-Nova feature ID `10003` (`avc_spoof`).
- Detects the actual SUSFS GKI 5.15 AVC state ABI after patching. It supports
  both a shared boolean (`READ_ONCE`/`WRITE_ONCE`) and a shared
  `static_key_false` (`static_key_enabled`/`static_branch_enable`/`disable`).
  The Manager handler is wired to the exact state used by the AVC audit hook
  and SUSFS control path.
- Uses the AVC-only changes from SukiSU-Nova PR #1058, pinned to head
  `119983f4dd8ca79dc69324cd358a73e104e35ab1` and base
  `4bec532dd447e2852aa8932afa768255350c103a`.
- The PR is open/unmerged and its author reports testing on Linux 5.4.
  This builder deliberately excludes its Linux <5.10 SELinux-hide compatibility
  changes; only the AVC handler and required registration changes are applied.
- The build validates the state definition, AVC audit hook, and SUSFS control path,
  then verifies the ABI-matched handler and emits `avc-spoof-build-proof.txt`.
  This is not proof of runtime behavior. Confirm the Manager reports
  **AVC Log Spoofing: Supported** after booting the resulting kernel.

The AnyKernel3 installer retains the requested device checks (`sapphiren`,
`sapphire`), Android 13–17 support, boot partition flow, and exact properties
from the supplied installer specification.


## AnyKernel3 template

This builder embeds and uses the AnyKernel3 archive supplied by the user in
`AnyKernel3/`. The packaging step copies that template as-is and adds only the
freshly built, KPM-patched `Image`. It does not clone or replace AnyKernel3
from another repository, and it preserves the supplied `anykernel.sh`
settings, helper binaries, modules, and install logic.

## KPM v7 build fix

The pinned KernelPatch ARM64 `kpimg` Makefile is patched at build time to add
`-fno-stack-protector` to its ARM64 CFLAGS. This avoids host GCC distro defaults
emitting unresolved `__stack_chk_guard` and `__stack_chk_fail` references in
the freestanding kpimg payload. This does not change the kernel's own stack
protector configuration or the supplied AnyKernel3 installer.


## v8 — ARM64 kpimg stack-protector fix (researched against branch `bk`)

The `bk` branch integrates SukiSU-Nova from its `builtin` branch and enables `CONFIG_KPM=y`; its SukiSU bridge uses ABI v2 and resolves `__arm64_sys_truncate`. The matching KernelPatch payload is still built separately and injected into the final Image.

The previous v7 patch had a detection bug: upstream `kernel/Makefile` already contained `-fno-stack-protector` in `X86_CFLAGS`, so a generic substring check incorrectly concluded the ARM64 compiler flags were fixed. v8 checks and inserts the exact `CFLAGS += -fno-stack-protector` assignment in the ARM64 CFLAGS section, then scans all ARM64 object files for unresolved `__stack_chk_guard` / `__stack_chk_fail` before accepting `kpimg`.

This is a source-level build fix, not a claim that a full GitHub Actions build or device boot has already passed.


## v9 — fix KernelPatch GOT/PLT linker failure

The GitHub Actions run 45033755763 reached the ARM64 `kpimg.elf` link stage.
The stack-protector references were gone, but `kpimg.lds` rejected `.got.plt`
and `.got` with `Unexpected GOT/PLT entries detected!` and `Unexpected GOT
detected!`. The upstream ARM64 `CFLAGS` did not disable PIC/PIE, while the
Ubuntu cross-GCC toolchain can default to PIE. v9 adds `-fno-pic -fno-pie`
to the ARM64 freestanding `CFLAGS`, separately from the x86 flags, and
verifies both flags before building. The linker script's zero-GOT assertions
remain intact; no GOT section is accepted or silently discarded.

This is a targeted correction based on the actual Actions log. It still
requires a new Actions run to validate the resulting `kpimg` link, kptools
build, Image injection, and AnyKernel3 packaging.


## v10 — KernelPatch TARGET_COMPILE environment fix

The Actions run `45034650043` completed the Linux 5.15 Image build and confirmed
`__arm64_sys_truncate` exists, then stopped while parsing KernelPatch's
`kernel/Makefile` with `TARGET_COMPILE not set`. The pinned KernelPatch Makefile
checks this variable before defining its cross tools. The KPM build script now
exports `TARGET_COMPILE=aarch64-linux-gnu-` into the process environment and
also passes it explicitly to `make`, ensuring the prefix is visible at Makefile
parse time and to nested build commands. The prior no-stack-protector and
no-PIC/no-PIE flags and linker assertions are preserved.

This archive has passed local ZIP integrity and shell syntax checks only; run
GitHub Actions to validate the complete KPM build, image injection, AnyKernel3
packaging, and artifact upload.
