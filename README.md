# Sapphire GKI 5.15 Kernel Builder

Builder kernel untuk Xiaomi Redmi Note 13 4G (codename: Sapphire).

## Platform

- Kernel source: `The-Angel-Place-Sapphire/kernel_xiaomi_sapphire`
- Branch: `lineage-23.2`
- Kernel: **GKI Linux 5.15**
- Defconfig: `vendor/sapphire_defconfig`
- Architecture: ARM64
- Toolchain: Neutron Clang
- Output: satu ZIP AnyKernel3 yang bisa langsung di-flash melalui custom recovery yang kompatibel.

## Fitur root

| Fitur | Keterangan |
|---|---|
| SukiSU-Nova | Root solution dan integrasi Manager |
| SUSFS | Fitur penyamaran/virtualisasi filesystem yang disediakan SUSFS |
| KPM | KernelPatch Module, termasuk payload `kpimg` yang disesuaikan dengan bridge SukiSU-Nova |
| AVC Log Spoofing | Integrasi eksperimental SukiSU-Nova feature ID `10003` untuk Linux 5.15 |

Fitur di atas adalah fitur yang disiapkan oleh konfigurasi builder. Dukungan runtime tetap harus diuji pada perangkat setelah kernel berhasil boot.

## Cara build

1. Upload isi repository ini ke repository GitHub.
2. Buka tab **Actions**.
3. Pilih workflow **Sapphire GKI 5.15 Kernel Build**.
4. Tekan **Run workflow**.
5. Setelah workflow berhasil, unduh artifact `Sapphire-GKI-5.15-Flashable`.
6. Ekstrak artifact. File ZIP di dalamnya adalah installer kernel AnyKernel3 yang langsung bisa di-flash.

## Instalasi

1. Pastikan perangkat sesuai dengan target `sapphire` / `sapphiren`.
2. Simpan backup boot image atau siapkan cara untuk memulihkan kernel sebelumnya.
3. Flash ZIP installer secara langsung melalui recovery yang kompatibel.
4. Reboot dan periksa status root, SUSFS, serta KPM melalui Manager yang sesuai.

**Peringatan:** build yang berhasil tidak otomatis menjamin kernel aman atau berhasil boot pada semua firmware. Jangan flash pada perangkat lain. Siapkan boot image cadangan sebelum instalasi.

## Struktur project

- `.github/workflows/build.yml` — workflow build otomatis.
- `scripts/` — script clone source, integrasi root, build, verifikasi, dan packaging.
- `AnyKernel3/` — template installer AnyKernel3.
- Output installer dibuat sebagai satu ZIP flashable; tidak dibungkus lagi di dalam ZIP distribusi lain.
