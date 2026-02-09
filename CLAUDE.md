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
└── evk/                      # Pre-built images ready for flashing
scripts/
└── apply-platform.sh         # Switch between EVK/SRG configs
vendor-reference/             # Original vendor files (reference only)
porting_guide.md              # Detailed notes, progress, troubleshooting
```

## Hardware: EVK vs SRG

| Feature | EVK | SRG |
|---------|-----|-----|
| DDR | 6GB (3G+3G) | 4GB (3G+1G) |
| Console UART | UART2 `ttymxc1` | UART4 `ttymxc3` |
| Earlycon | `0x30890000` | `0x30A60000` |
| External RTC | None | PCF85063 @ I2C3 |

## Quick Commands

### Switch Platform & Build
```bash
# Apply EVK configuration
~/srg-imx8pl-android14-porting/scripts/apply-platform.sh evk

# Build bootloader
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
./imx-make.sh bootloader -j$(nproc)
```

### Flash SD Card
```bash
cd ~/srg-imx8pl-android14-porting/flash-images/evk
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdb
```

### Analyze Vendor WIC Image
```bash
# Decompress
zstd -d image.rootfs.wic.zst -o wic.img

# Check console settings from U-Boot
dd if=wic.img of=flash.bin bs=1k skip=32 count=1600
strings flash.bin | grep "console="

# Check DTB memory config
OFFSET=$((16384 * 512))
sudo mount -o loop,offset=$OFFSET,ro wic.img /mnt
dtc -I dtb -O dts /mnt/imx8mp-evk.dtb | grep -A5 "memory@"
```

## Current Status
- [x] RTC (PCF85063) added to device tree
- [x] Dual-platform config (EVK/SRG) created
- [x] EVK bootloader built and images prepared
- [x] WIC image analysis completed
- [ ] **BLOCKING:** SRG DDR timing issue - vendor file may be for 8GB
- [ ] Test EVK boot on EVK hardware
- [ ] Obtain correct 4GB DDR timing from vendor

## Known Issues

| Issue | Impact | Action |
|-------|--------|--------|
| SRG DDR timing mismatch | Board won't boot | Request 4GB timing from vendor |
| tee.bin missing | Non-fatal warning | Safe to ignore for bring-up |
| GKI kernel overwrite | boot.img replaced | `cp boot-imx.img boot.img` |

## Key Paths
- **Build root:** `/mnt/data/imx-android-14.0.0_2.2.0/android_build`
- **U-Boot:** `vendor/nxp-opensource/uboot-imx/`
- **Kernel DTS:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/`
- **imx-mkimage:** `vendor/nxp-opensource/imx-mkimage/`
