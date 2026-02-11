# SRG-iMX8PL Android 14 Porting Notes

**Date:** 2026-02-05 (Updated: 2026-02-11)
**Platform:** SRG-iMX8PL (based on NXP i.MX8MP EVK)
**OS:** Android 14

## Overview

This note documents the porting of Android 14 to the SRG-iMX8PL custom board, including RTC integration, 4GB DDR timing support, and debugging the boot freeze issue.

## Hardware Differences: EVK vs SRG

| Feature | NXP i.MX8MP EVK | SRG-iMX8PL |
|---------|-----------------|------------|
| DDR Size | 6GB (3G + 3G) | 4GB (3G + 1G) |
| Console UART | UART2 (`ttymxc1`) | UART4 (`ttymxc3`) |
| UART Base | `0x30890000` | `0x30A60000` |
| External RTC | None | PCF85063ATL @ I2C3 0x51 |

---

## Dual Platform Configuration

A dual-platform build system was established to support both EVK and SRG boards simultaneously.

### Directory Structure
```
~/srg-imx8pl-android14-porting/
├── kernel/
│   └── dts/
│       ├── imx8mp-evk.dts        # SRG (Modified): 4GB DDR, UART4, USB Host
│       └── imx8mp-evk.dts.orig   # EVK (Original): 6GB DDR, UART2, USB OTG
├── uboot/
│   ├── board/
│   │   ├── lpddr4_timing.c       # SRG: 4GB Timing (3000MHz, official AAEON)
│   │   ├── lpddr4_timing.c.orig  # EVK: 6GB/8GB Timing
│   │   ├── imx8mp_evk.h          # SRG: Memory Map, UART4 Base
│   │   └── imx8mp_evk.h.orig     # EVK: Memory Map, UART2 Base
│   ├── dts/
│   │   ├── imx8mp-evk.dts        # SRG: U-Boot DTS (UART4, console=ttymxc3)
│   │   └── imx8mp-evk.dts.orig   # EVK: U-Boot DTS (UART2, console=ttymxc1)
│   └── spl_dts/
│       ├── imx8mp-evk-u-boot.dtsi       # SRG: SPL DTSI (UART4 bootph-pre-ram)
│       └── imx8mp-evk-u-boot.dtsi.orig  # EVK: SPL DTSI (UART2)
├── flash-images/
│   ├── evk/                  # Pre-built EVK images for flashing
│   └── srg/                  # Pre-built SRG images for flashing
├── patches/                  # Official patches (Source of Truth)
├── scripts/
│   ├── apply-platform.sh     # One-command platform switch (deploys all files)
│   ├── restore_to_original.sh # Restore EVK defaults to Android Build
│   └── build/                # Build helper scripts (AndroidUboot.sh, pad_image.sh)
└── vendor-reference/         # Original vendor files

/mnt/data/unmodified_source/          # Extracted original NXP source code (Reference)
/mnt/data/imx-android-14.0.0_2.2.0/android_build/  # Actual Android Build Tree
```

### Switching Platforms
To switch the Android build tree between EVK and SRG configurations:

```bash
# Apply SRG configuration (Uses standard modified files)
./scripts/apply-platform.sh srg

# Apply EVK configuration (Uses *.orig files)
./scripts/apply-platform.sh evk
```

---

## Complete Modification Audit

All changes to the Android build tree vs unmodified NXP source (11 files across 4 repos):

### Repo 1: `vendor/nxp-opensource/uboot-imx/` (6 files)

| # | File | Change | Status |
|---|------|--------|--------|
| 1 | `include/configs/imx8mp_evk.h` | DDR 4GB + UART4 base + console ttymxc3 | ✅ Correct |
| 2 | `board/freescale/imx8mp_evk/lpddr4_timing.c` | 4GB/3000MHz timing (official AAEON) | ✅ Correct |
| 3 | `board/freescale/imx8mp_evk/imx8mp_evk.c` | Added uart4_pads[], conditional UART init | ✅ Correct |
| 4 | `arch/arm/dts/imx8mp-evk-u-boot.dtsi` | &uart2→&uart4 bootph-pre-ram, pinctrl_uart4 | ✅ Correct |
| 5 | `arch/arm/dts/imx8mp-evk.dts` | console=ttymxc3, stdout-path=&uart4, uart4 okay | ✅ Fixed (2026-02-11) |
| 6 | `configs/imx8mp_evk_android_defconfig` | BOOTCOMMAND="boota" | ✅ Correct (needed without saved env) |

### Repo 2: `device/nxp/` (2 files)

| # | File | Change | Status |
|---|------|--------|--------|
| 7 | `common/tools/imx-make.sh` | ENABLE_GKI default 1→0 | ✅ Intentional |
| 8 | `imx8m/evk_8mp/AndroidUboot.sh` | Added `SPD=none` for non-trusty ATF | ✅ Key TEE fix |

### Repo 3: `vendor/nxp-opensource/kernel_imx/` (2 files)

| # | File | Change | Status |
|---|------|--------|--------|
| 9 | `arch/arm64/boot/dts/freescale/imx8mp-evk.dts` | UART4 + USB host + RTC + regulators | ✅ Correct |
| 10 | `arch/arm64/configs/gki_defconfig` | CONFIG_DEBUG_INFO_BTF=y→n | ✅ Build fix |

### Repo 4: `vendor/nxp-opensource/imx-mkimage/` (1 file)

| # | File | Change | Status |
|---|------|--------|--------|
| 11 | `scripts/pad_image.sh` | Skip missing tee.bin instead of error | ✅ Build fix for SPD=none |

### Not Yet Modified

| File | Issue |
|------|-------|
| `device/nxp/imx8m/evk_8mp/BoardConfig.mk:135` | `androidboot.console=ttymxc1` should be `ttymxc3` (userspace only) |

---

## Task 1: RTC (PCF85063ATL) - Resolved

**Hardware:** PCF85063ATL @ I2C3 0x51

**File:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts`

```dts
&i2c3 {
    rtc: pcf85063@51 {
        compatible = "nxp,pcf85063a";
        reg = <0x51>;
    };
};
```

---

## Task 2: Memory 4GB DDR Configuration - Resolved

**Source:** `meta-aaeon-nxp` (kirkstone branch)
**Patch File:** `patches/001-srg-imx8pl-4gddr-uboot-all.patch`

### U-Boot Header Changes (`imx8mp_evk.h`)
```c
/* SRG-iMX8PL: 4GB DDR */
#define PHYS_SDRAM_SIZE       0xC0000000   /* 3 GB (below 4GB boundary) */
#define PHYS_SDRAM_2_SIZE     0x40000000   /* 1 GB (above 4GB boundary) */

/* UART4 Console for SRG */
#define CFG_MXC_UART_BASE     UART4_BASE_ADDR
```

---

## Task 3: Kernel USB Configuration - Resolved

Modified `imx8mp-evk.dts` (Kernel) to:
1. **Add Regulators**: `reg_usb1_vbus` and `reg_usb2_vbus` (GPIO1_05/06)
2. **Force Host Mode**: `dr_mode = "host"` on `&usb_dwc3_0` and `&usb_dwc3_1`
3. **Disable Type-C**: Disabled `ptn5110` and `cbtl04gp`

---

## Task 4: Bootloader Console & TEE - Resolved

### Problem
The SRG board uses UART4 for console (EVK uses UART2). Multiple issues prevented boot:
1. Non-trusty ATF build had no `SPD` flag, defaulting to optee which requires `tee.bin`
2. U-Boot DTS had incomplete UART migration (stdout-path and console still on UART2)
3. ATF console hardcoded to UART2 (`0x30890000`)

### Solution
1. **`SPD=none` in ATF**: Added to `AndroidUboot.sh` non-trusty branch. Tells BL31 to skip TEE.
2. **`pad_image.sh` patched**: Skips missing `tee.bin` instead of erroring.
3. **U-Boot DTS fully migrated to UART4 (2026-02-11)**: Fixed `stdout-path = &uart4`, `console=ttymxc3`, `uart4 status = "okay"`.
4. **ATF UART4 (2026-02-11)**: Added `IMX_BOOT_UART_BASE=0x30A60000` to ATF build command.
5. **`CONFIG_BOOTCOMMAND="boota"`**: Changed from `distro_bootcmd` chain because we flash our own U-Boot without saved env.

### Boot Progress (2026-02-11)
```
DDRINFO: ddrphy calibration done     ✅ DDR 4GB working
SEC0: RNG instantiated               ✅
Normal Boot                          ✅
Trying to boot from MMC1             ✅ SPL → ATF → U-Boot
...
Run /init as init process            ✅ Kernel booted!
init: init first stage started!      ✅ Android init running
init: Loading module mxc-clk.ko      ✅ Kernel modules loading
```

Full boot chain working: SPL → ATF → U-Boot → Kernel → Android init first stage.

---

## Build & Flash Workflow

### Environment Setup
```bash
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export AARCH32_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
export _JAVA_OPTIONS="-Xmx16g"
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
```

### Build Components
- **U-Boot**: `./imx-make.sh bootloader -j$(nproc)`
- **Kernel (boot.img)**:
    ```bash
    ./imx-make.sh kernel -j$(nproc)  # Compiles kernel/dtb
    make bootimage -j$(nproc)        # Packs boot.img
    ```

### Flash to SD Card (SRG)
```bash
cd ~/srg-imx8pl-android14-porting/flash-images/srg
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdX
```

### Copy Build Artifacts
```bash
cp /mnt/data/imx-android-14.0.0_2.2.0/android_build/out/target/product/evk_8mp/obj/UBOOT_COLLECTION/u-boot-imx8mp.imx \
   ~/srg-imx8pl-android14-porting/flash-images/srg/u-boot-imx8mp.imx
```

---

## Next Steps

- [x] Obtain correct 4GB DDR timing (Found in meta-aaeon-nxp)
- [x] Apply Kernel USB fixes (Host mode, VBUS)
- [x] Fix U-Boot DTS UART4 migration (stdout-path, console, status)
- [x] Audit all build tree modifications vs unmodified source
- [x] Fix ATF UART console (IMX_BOOT_UART_BASE=0x30A60000)
- [x] Boot to kernel + Android init first stage
- [ ] Debug any remaining boot issues (module loading, second stage init)
- [ ] Verify DDR detection (4GB)
- [ ] Verify USB functionality (Mouse/Keyboard)
- [ ] Fix `androidboot.console=ttymxc3` in BoardConfig.mk
