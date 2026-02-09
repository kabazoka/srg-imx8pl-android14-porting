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

### U-Boot Header Changes (`imx8mp_evk.h`)

```c
/* SRG-iMX8PL: 4GB DDR */
#define PHYS_SDRAM_SIZE       0xC0000000   /* 3 GB (below 4GB boundary) */
#define PHYS_SDRAM_2_SIZE     0x40000000   /* 1 GB (above 4GB boundary) */

/* UART4 Console for SRG */
#define CFG_MXC_UART_BASE     UART4_BASE_ADDR
```

### Console Boot Args
```c
"console=ttymxc3,115200 earlycon=ec_imx6q,0x30A60000,115200"
```

---

## Boot Freeze Debugging

### Problem
SRG board freezes during kernel boot. EVK debug port shows no output.

### Root Cause Analysis

#### 1. UART Mismatch
- EVK uses UART2 (`ttymxc1`, base `0x30890000`)
- SRG uses UART4 (`ttymxc3`, base `0x30A60000`)

#### 2. DDR Timing Mismatch (Critical!)
Discovered by comparing DDR address mapping register `0x3d400200`:

| Config | Value | Notes |
|--------|-------|-------|
| EVK (6GB) | `0x16` | NXP original |
| SRG (vendor file) | `0x18` | May be for 8GB hardware |

**Finding:** The vendor-provided `lpddr4_timing_8g.c` is identical to the "4GB" timing file. This suggests the DDR timing was designed for 8GB hardware, not 4GB!

### Resolution
Request correct 4GB DDR timing from vendor, or use NXP DDR PHY config tool to regenerate timing parameters for 4GB hardware.

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
# Typical output:
# wic.img1   16384   186775   boot (vfat)
# wic.img2  196608  ...       rootfs (ext4)
```

### 3. Extract U-Boot Console Settings
```bash
# Extract U-Boot from beginning of image
dd if=wic.img of=flash-extract.bin bs=1k skip=32 count=1600

# Check console settings
strings flash-extract.bin | grep -E "console=|ttymxc"
# Example output: console=ttymxc3,115200 earlycon=ec_imx6q,0x30A60000,115200
```

### 4. Mount Boot Partition and Check DTB
```bash
OFFSET=$((16384 * 512))  # Calculate byte offset
sudo mount -o loop,offset=$OFFSET,ro wic.img boot_part/

# Extract memory configuration from DTB
dtc -I dtb -O dts boot_part/imx8mp-evk.dtb 2>/dev/null | grep -A5 "memory@"
# Example output:
# memory@40000000 {
#     device_type = "memory";
#     reg = <0x00 0x40000000 0x00 0xc0000000 0x01 0x00 0x00 0xc0000000>;
# };

sudo umount boot_part
```

### Interpreting Memory `reg` Property
```
reg = <addr_hi addr_lo size_hi size_lo ...>

Example for 6GB (3G + 3G):
<0x00 0x40000000 0x00 0xc0000000   0x01 0x00 0x00 0xc0000000>
  |      |         |      |         |    |    |      |
  Bank1 @ 0x40000000, size 3GB    Bank2 @ 0x100000000, size 3GB
```

---

## Build & Flash Workflow

### Environment Setup
```bash
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
```

### Build Bootloader Only
```bash
./imx-make.sh bootloader -j$(nproc)
```

### Flash to SD Card
```bash
cd ~/srg-imx8pl-android14-porting/flash-images/evk
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdb
```

### GKI Kernel Image Issue
`imx-make.sh` overwrites `boot.img` with GKI kernel when `enable_gki=1`. Workaround:
```bash
# After build, copy custom kernel back
cp out/target/product/evk_8mp/boot-imx.img out/target/product/evk_8mp/boot.img
```

---

## Known Issues

| Issue | Status | Notes |
|-------|--------|-------|
| tee.bin missing | Non-fatal | Non-Trusty manifest, safe for bring-up |
| GKI kernel overwrite | Workarounded | Copy boot-imx.img → boot.img |
| SRG DDR timing | **Blocking** | Vendor file may be for 8GB, not 4GB |

---

## Next Steps

- [ ] Obtain correct 4GB DDR timing from vendor
- [ ] Test EVK build on EVK hardware
- [ ] Verify DDR detection: U-Boot `bdinfo` should show 4GB
- [ ] Verify RTC: `hwclock -r` in Android
- [ ] Full Android boot to launcher
