# SRG-iMX8PL Android 14 Porting

## Project Overview
Porting Android 14 (NXP BSP imx-android-14.0.0_2.2.0) to the SRG-iMX8PL custom board based on i.MX8M Plus.

This repo tracks only the **modified files** — not the full Android source tree.

## Directory Layout
```
uboot/
├── evk/                      # EVK config (6GB DDR, UART2)
│   ├── imx8mp_evk.h
│   └── lpddr4_timing.c
└── srg/                      # SRG config (4GB DDR, UART4)
    ├── imx8mp_evk.h
    └── lpddr4_timing.c
flash-images/
├── evk/                      # EVK build artifacts
└── srg/                      # SRG build artifacts (Ready for testing)
patches/                      # Official patches from meta-aaeon-nxp
scripts/
└── apply-platform.sh         # Switch between EVK/SRG configs
vendor-reference/             # Original vendor files
```

## Hardware: EVK vs SRG

| Feature | EVK | SRG |
|---------|-----|-----|
| DDR | 6GB (3G+3G) | 4GB (3G+1G) |
| Console UART | UART2 `ttymxc1` | UART4 `ttymxc3` |
| Earlycon | `0x30890000` | `0x30A60000` |
| External RTC | None | PCF85063 @ I2C3 |

## Quick Commands

> [!IMPORTANT]
> **ALWAYS** use the following wrapper scripts/tools when available. They handle environment setup and arguments correctly.
> - **Build:** `./imx-make.sh` (instead of `make`)
> - **Flash:** `./imx-sdcard-partition.sh` (instead of `dd` or other tools)

### Switch Platform & Build
```bash
# Apply SRG configuration
~/srg-imx8pl-android14-porting/scripts/apply-platform.sh srg

# Build bootloader
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export AARCH32_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
export _JAVA_OPTIONS="-Xmx16g"
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
./imx-make.sh bootloader -j$(nproc)
```

### Flash SD Card (SRG)
```bash
cd ~/srg-imx8pl-android14-porting/flash-images/srg
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdb
```

### Analyze Vendor WIC Image
```bash
zstd -d image.rootfs.wic.zst -o wic.img
dd if=wic.img of=flash.bin bs=1k skip=32 count=1600
strings flash.bin | grep "console="
```

## Current Status
- [x] RTC (PCF85063) added to device tree
- [x] Dual-platform config (EVK/SRG) created
- [x] **DDR Timing Resolved** (Official patch applied)
- [x] SRG images built and ready in `flash-images/srg/`
- [x] **Bootloader TEE/UART4 Fixed** (No-TEE build, UART4 console)
- [ ] Flash and boot test on SRG hardware
- [ ] Verify USB functionality

## Known Issues

| Issue | Impact | Status |
|-------|--------|--------|
| SRG DDR timing | Board freeze | **Resolved** (Patched) |
| tee.bin missing | Build failure | **Resolved** (`pad_image.sh` patched to skip) |
| Boot hang (TEE) | No U-Boot output | **Resolved** (optee node disabled in DTS) |
| USB Port Limit | Potential | Kernel patch applied |

## Key Paths
- **Build root:** `/mnt/data/imx-android-14.0.0_2.2.0/android_build`
- **U-Boot:** `vendor/nxp-opensource/uboot-imx/`
- **Patches:** `~/srg-imx8pl-android14-porting/patches/`
