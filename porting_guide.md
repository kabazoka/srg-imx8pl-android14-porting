# SRG-iMX8PL Android 14 Porting Notes

**Date:** 2026-02-05
**Platform:** SRG-iMX8PL (based on NXP i.MX8MP EVK)
**OS:** Android 14

## Overview

This note documents the completion of remaining porting tasks: RTC integration and 4GB DDR timing support.

## Version Control Strategy

A Git repository was established to manage modifications to key files, separating them from the massive Android build tree for better traceability.

- **Repo Location:** `~/srg-imx8pl-android14-porting/`
- **Tracked Files:**
    - DTS modifications
    - U-Boot board files (DDR timing)
    - U-Boot configs (Header files)

## Task 1: RTC (PCF85063ATL)

**Hardware:** PCF85063ATL @ I2C3 0x51

### Modifications

**File:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts`

Added the RTC node under `&i2c3`:

```dts
&i2c3 {
    /* ... existing devices ... */

    rtc: pcf85063@51 {
        compatible = "nxp,pcf85063a";
        reg = <0x51>;
    };
};
```

**Verification:**
After booting:
```bash
adb shell ls /dev/rtc*
adb shell hwclock -r
adb shell cat /proc/driver/rtc
```

## Task 2: Memory 4GB DDR Timing

**Objective:** Adjust memory configuration from EVK (6GB) to SRG typical (4GB), using Vendor provided timing files.

### Analysis
Vendor files were located in `/mnt/data/tmp/`:
- `lpddr4_timing_8g.c`: DDR timing settings (seems compatible with 4GB based on register analysis).
- `imx8mp_evk_8g.h`: Board configuration header.

**Changes Implemented:**
1.  **Replaced Timing File:**
    - Source: `/mnt/data/tmp/lpddr4_timing_8g.c`
    - Dest: `vendor/nxp-opensource/uboot-imx/board/freescale/imx8mp_evk/lpddr4_timing.c`
2.  **Modified Header File:**
    - File: `vendor/nxp-opensource/uboot-imx/include/configs/imx8mp_evk.h`
    - Adjusted memory banks for 4GB (3GB + 1GB split):
        ```c
        /* Totally 4GB DDR */
        #define PHYS_SDRAM_SIZE 0xC0000000      /* 3 GB (below 4GB boundary) */
        #define PHYS_SDRAM_2_SIZE 0x40000000    /* 1 GB (above 4GB boundary) */
        ```
    - **UART Console:** Kept Vendor setting `console=ttymxc3` (UART4) which matches SRG schematic, replacing EVK's UART2.

## Execution Log

### Git Setup
```bash
mkdir -p ~/srg-imx8pl-android14-porting/{kernel/dts,uboot/{board,configs}}
cd ~/srg-imx8pl-android14-porting
git init
# Copied baseline EVK files and Vendor reference files
git commit -m "Initial: EVK baseline files for SRG-iMX8PL porting"
```

### Applied Changes
```bash
# RTC Change
# (Edited imx8mp-evk.dts)
git commit -m "RTC: Add PCF85063 to i2c3 for SRG-iMX8PL"

# DDR Change
# (Copied vendor timing and edited header)
git commit -m "DDR: Switch to 4GB timing from Vendor Yocto"
```

## Build & Troubleshooting Notes

### U-Boot Build
The correct defconfig for Android 14 on i.MX8MP EVK is `imx8mp_evk_android_defconfig`.

```bash
cd vendor/nxp-opensource/uboot-imx
make imx8mp_evk_android_defconfig
```

> **Note:** Do not run make from the root `android_build` dir for just defconfig, or use the `imx-make.sh` script for the full build.

### Full Build (Android 14)
**Lunch Target:**
Android 14 uses a new naming convention `<product>-<release>-<variant>`.
- Valid target: `evk_8mp-trunk_staging-userdebug`
- Faster build (eng): `evk_8mp-trunk_staging-eng`

**Command:**
```bash
cd android_build
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
./imx-make.sh -j$(nproc)
```

### Issues Encountered
**CLANG_PATH Error:**
The build failed with `CLANG_BIN ... does not exist`. The env var `CLANG_PATH` was pointing to a non-existent directory.
**Fix:** Point to the correct prebuilts directory in the current source tree.

```bash
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export AARCH32_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
export _JAVA_OPTIONS="-Xmx16g"
```
(Specific version found was `clang-r510928` but the makefile expects the path to the parent directory usually, or the specific version depending on `kernel.mk`).

## Build Progress

### 2026-02-06: First Full Build Attempt

**Build command:**
```bash
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
nohup ./imx-make.sh -j$(nproc) &
```

**Result:** Build completed successfully. `flash.bin` generated at:
```
vendor/nxp-opensource/imx-mkimage/iMX8M/flash.bin
```

**Non-fatal warning:**
```
ERROR: ./../scripts/pad_image.sh: Could not find file tee.bin. Exiting.
```
- **Root cause:** The manifest `imx-android-14.0.0_2.2.0.xml` is the non-Trusty variant and does not include OP-TEE (`imx-optee-os` project is absent).
- **Impact:** The `pad_image.sh` script uses `exit 0` (not `exit 1`), so the build continues. The resulting `flash.bin` is valid but without TEE.
- **Action:** Safe to ignore for initial bring-up. For production, either:
  - Switch to Trusty manifest (`imx-trusty-android-14.0.0_2.2.0.xml`)
  - Or build OP-TEE separately and place `tee.bin` in `imx-mkimage/iMX8M/`

**Generated boot image contents** (in `imx-mkimage/iMX8M/`):
- `flash.bin` — Final bootloader image (SPL + ATF + U-Boot FIT)
- `bl31.bin` — ARM Trusted Firmware (ATF/TF-A)
- `u-boot-spl.bin`, `u-boot-spl-ddr.bin` — SPL with DDR init
- `u-boot-nodtb.bin` — U-Boot proper
- LPDDR4 PMU training firmware binaries

## Next Steps

- [ ] Flash `flash.bin` to SRG-iMX8PL board and verify U-Boot boot
- [ ] Verify DDR 4GB detection in U-Boot (`bdinfo` / `md` commands)
- [ ] Verify UART4 console output (`ttymxc3`)
- [ ] Verify RTC (`hwclock -r` after Linux boots)
- [ ] Test full Android boot to launcher
- [ ] Evaluate TEE requirement (Trusty vs OP-TEE) for production
