# SRG-iMX8PL Android 14 Porting

## Project Overview
Porting Android 14 (NXP BSP imx-android-14.0.0_2.2.0) to the SRG-iMX8PL custom board based on i.MX8M Plus.

This repo tracks only the **modified files** — not the full Android source tree.

## Directory Layout
```
kernel/dts/           - Device tree modifications (based on imx8mp-evk.dts)
uboot/board/          - U-Boot board files (DDR timing)
uboot/configs/        - U-Boot config headers (memory layout, console)
vendor-reference/     - Vendor-provided reference files (do not modify)
porting_guide.md      - Detailed porting notes, progress, and troubleshooting
```

## Key Paths (Android Build Tree)
- **Build root:** `/mnt/data/imx-android-14.0.0_2.2.0/android_build`
- **U-Boot:** `vendor/nxp-opensource/uboot-imx/`
- **Kernel DTS:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/`
- **imx-mkimage:** `vendor/nxp-opensource/imx-mkimage/`
- **Manifests:** `.repo/manifests/` (using `imx-android-14.0.0_2.2.0.xml`)

## Hardware Specifics
- **SoC:** NXP i.MX8M Plus
- **DDR:** 4GB LPDDR4 (3GB + 1GB split at 4GB boundary)
- **Console UART:** UART4 (`ttymxc3`) — differs from EVK's UART2
- **RTC:** PCF85063ATL on I2C3 @ 0x51
- **Base reference:** i.MX8MP EVK

## Build Commands
```bash
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export AARCH32_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
export _JAVA_OPTIONS="-Xmx16g"
./imx-make.sh -j$(nproc)
```

## Applying Changes to Build Tree
Copy modified files from this repo into the Android build tree before building:
```bash
# DDR timing
cp uboot/board/lpddr4_timing.c  <build>/vendor/nxp-opensource/uboot-imx/board/freescale/imx8mp_evk/

# U-Boot header
cp uboot/configs/imx8mp_evk.h   <build>/vendor/nxp-opensource/uboot-imx/include/configs/

# Kernel DTS
cp kernel/dts/imx8mp-evk.dts    <build>/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/
```

## Current Status
- [x] RTC (PCF85063) added to device tree
- [x] DDR switched to 4GB timing (vendor Yocto reference)
- [x] First full build completed (flash.bin generated, tee.bin warning is non-fatal)
- [ ] Flash and verify U-Boot on hardware
- [ ] Verify DDR 4GB, UART4, RTC on hardware
- [ ] Full Android boot test
- [ ] TEE integration (Trusty or OP-TEE) for production

## Known Issues
- **tee.bin missing warning:** Non-fatal. The non-Trusty manifest doesn't include OP-TEE. Safe to ignore for bring-up.
- **Defconfig:** Use `imx8mp_evk_android_defconfig` (not the standalone U-Boot one).
- **Lunch target:** Android 14 format is `evk_8mp-trunk_staging-userdebug`.
