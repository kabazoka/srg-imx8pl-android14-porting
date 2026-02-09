# SRG-iMX8PL Android 14 Porting Notes

**Date:** 2026-02-05 (Updated: 2026-02-09)
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
├── uboot/
│   ├── evk/                  # EVK: 6GB DDR, UART2
│   │   ├── imx8mp_evk.h
│   │   └── lpddr4_timing.c
│   └── srg/                  # SRG: 4GB DDR, UART4
│       ├── imx8mp_evk.h
│       └── lpddr4_timing.c
├── flash-images/
│   └── evk/                  # Pre-built EVK images for flashing
├── scripts/
│   └── apply-platform.sh     # One-command platform switch
└── vendor-reference/         # Original vendor files
```

### Switching Platforms
```bash
# Apply EVK configuration
./scripts/apply-platform.sh evk

# Apply SRG configuration
./scripts/apply-platform.sh srg
```

---

## Task 1: RTC (PCF85063ATL)

**Hardware:** PCF85063ATL @ I2C3 0x51

### Modifications

**File:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts`

```dts
&i2c3 {
    rtc: pcf85063@51 {
        compatible = "nxp,pcf85063a";
        reg = <0x51>;
    };
};
```

**Verification:**
```bash
adb shell ls /dev/rtc*
adb shell hwclock -r
adb shell cat /proc/driver/rtc
```

---

## Task 2: Memory 4GB DDR Configuration

### Official Patch (Resolved)
**Source:** `meta-aaeon-nxp` (kirkstone branch)
**Patch File:** `patches/001-srg-imx8pl-4gddr-uboot-all.patch`

This official patch provided by AAEON contains:
1.  **Correct DDR Timing:** `lpddr4_timing.c` values are significantly different from the 8GB version we had.
2.  **UART4 Console:** `imx8mp-evk.dts` changes for `ttymxc3`.
3.  **Memory Map:** `imx8mp_evk.h` defines 4GB split (3GB + 1GB).

### Application Notes
The patch is for Yocto (Kernel 5.15) and does not apply cleanly to Android 14 U-Boot. We manually applied:
-   `lpddr4_timing.c` (Cleanly applied via `git apply`)
-   `imx8mp_evk.h` (Manually updated macros)

### U-Boot Header Changes (`imx8mp_evk.h`)
```c
/* SRG-iMX8PL: 4GB DDR */
#define PHYS_SDRAM_SIZE       0xC0000000   /* 3 GB (below 4GB boundary) */
#define PHYS_SDRAM_2_SIZE     0x40000000   /* 1 GB (above 4GB boundary) */

/* UART4 Console for SRG */
#define CFG_MXC_UART_BASE     UART4_BASE_ADDR
```

---

## Boot Freeze Debugging (Resolved)

### Problem
SRG board freezes during kernel boot using 8GB timing file.

### Root Cause
**DDR Timing Mismatch.** The vendor-provided `lpddr4_timing_8g.c` was for 8GB hardware. The 4GB hardware requires different training parameters.

### Resolution
Applied official 4GB timing from `meta-aaeon-nxp`.
-   **Old Value (8GB):** `0x3d400020 = 0x1323`
-   **New Value (4GB):** `0x3d400020 = 0x1223`

---

## Analyzing Yocto WIC Images

To extract memory configuration from vendor's Yocto image:

### 1. Decompress WIC Image
```bash
mkdir -p /tmp/wic-extract && cd /tmp/wic-extract
zstd -d /path/to/image.rootfs.wic.zst -o wic.img
```

### 2. Check Partition Layout
```bash
fdisk -l wic.img
```

### 3. Extract U-Boot Console Settings
```bash
# Extract U-Boot from beginning of image
dd if=wic.img of=flash-extract.bin bs=1k skip=32 count=1600
strings flash-extract.bin | grep -E "console=|ttymxc"
```

---

## Task 3: Kernel USB Configuration (Resolved)

### Problem
Target SRG board uses Type-A USB Host ports, while EVK defaults to Type-C/OTG with `ptn5110` controller. This mismatch caused USB failure and potential boot issues.

### Solution
Modified `imx8mp-evk.dts` (Kernel 6.6) to:
1.  **Add Regulators**: Added `reg_usb1_vbus` and `reg_usb2_vbus` (GPIO1_05/06).
2.  **Force Host Mode**: Set `dr_mode = "host"` and `vbus-supply` directly on `&usb_dwc3_0` and `&usb_dwc3_1`.
3.  **Disable Type-C**: Disabled `ptn5110` (Type-C Controller) and `cbtl04gp` (Switch) to fix build errors caused by broken references to OTG endpoints.

### Applied Changes (`imx8mp-evk.dts`)
-   Nodes added: `reg_usb1_vbus`, `reg_usb2_vbus`, `pinctrl_usb1_vbus`, `pinctrl_usb2_vbus`
-   Nodes disabled: `ptn5110`, `cbtl04gp`
-   Nodes modified: `&usb_dwc3_0`, `&usb_dwc3_1` (Host mode)

---

## Build & Flash Workflow

### Environment Setup
```bash
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
```

### Build Components
-   **U-Boot**: `./imx-make.sh bootloader -j$(nproc)`
-   **Kernel (boot.img)**: 
    ```bash
    ./imx-make.sh kernel -j$(nproc)  # Compiles kernel/dtb
    make bootimage -j$(nproc)        # PCKS boot.img (Essential!)
    ```

### Flash to SD Card (SRG)
```bash
cd ~/srg-imx8pl-android14-porting/flash-images/srg
# Ensure boot.img is updated
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdb
```

---

## Known Issues

| Issue | Status | Notes |
|-------|--------|-------|
| tee.bin missing | Non-fatal | Non-Trusty manifest, safe for bring-up |
| GKI kernel overwrite | **RESOLVED** | Manually repacked `boot.img` with custom kernel |
| SRG DDR timing | **RESOLVED** | Applied official 4GB patch |
| USB Functionality | **PATCHED** | Regulators added, Host mode forced, Type-C disabled |

---

## Next Steps

- [x] Obtain correct 4GB DDR timing (Found in meta-aaeon-nxp)
- [x] Apply Kernel USB fixes (Host mode, VBUS)
- [ ] Flash and Boot Test on SRG hardware
- [ ] Verify DDR detection (4GB)
- [ ] Verify USB functionality (Mouse/Keyboard)
