# Kernel Hang Debug Tests for EVK

## Background

The GKI kernel hangs at "Starting kernel ..." with zero earlycon output.
Previous manual test at 0x50000000 was **INVALID** because ATF's RDC blocks
CPU reads from 0x50000000-0x58000000 (BL32/TEE region).

## Partition Layout (SD card, non-dual)

| Partition      | Start sector | Hex      | Size    |
|----------------|-------------|----------|---------|
| dtbo_a         | 16384       | 0x4000   | 4 MiB   |
| dtbo_b         | 24576       | 0x6000   | 4 MiB   |
| boot_a         | 32768       | 0x8000   | 64 MiB  |
| boot_b         | 163840      | 0x28000  | 64 MiB  |
| init_boot_a    | 294912      | 0x48000  | 8 MiB   |
| init_boot_b    | 311296      | 0x4C000  | 8 MiB   |
| vendor_boot_a  | 327680      | 0x50000  | 64 MiB  |
| vendor_boot_b  | 458752      | 0x70000  | 64 MiB  |
| vbmeta_a       | 27250688    | 0x19FE800| 1 MiB   |
| vbmeta_b       | 27254784    | 0x19FF800| 1 MiB   |

---

## Test 1: Manual Boot at Valid Address (Tests memmove hypothesis)

Purpose: Load kernel to a 2MB-aligned address that does NOT overlap with
the booti relocation target, AND is in an RDC-readable region (<0x50000000).

```
# ============================================
# Run these in U-Boot console (stop autoboot)
# ============================================

# Step 1: Select SD card (mmc1)
mmc dev 1

# Step 2: Read kernel from boot_a partition
#   boot_a starts at sector 0x8000
#   Skip 8 sectors (4096-byte boot header v4)
#   Kernel = 35699200 bytes = 0x1105D sectors
#   Load to 0x48000000 (2MB-aligned, in RDC region 40 = readable)
mmc read 0x48000000 0x8008 0x1105D

# Step 3: Read DTBO from dtbo_a partition
#   dtbo_a starts at sector 0x4000
#   Total DTBO image = 85212 bytes ≈ 0xA7 sectors, read 0x100 to be safe
#   Load to 0x4D000000 (well above kernel end at ~0x4A2A0000)
mmc read 0x4D000000 0x4000 0x100

# Step 4: Verify kernel magic (should show: 4d5a40fa = MZ ARM64)
md.l 0x48000000 2

# Step 5: Verify DTB magic at offset 0x40 (should show: edfe0dd0 = FDT)
md.l 0x4D000040 2

# Step 6: Set full bootargs (MUST include earlycon + console)
setenv bootargs "earlycon=ec_imx6q,0x30890000,115200 console=ttymxc1,115200 init=/init firmware_class.path=/vendor/firmware loop.max_part=7 bootconfig transparent_hugepage=never swiotlb=65536 moal.mod_para=wifi_mod_para.conf pci=nomsi cma=1184M@0x400M-0x1000M"

# Step 7: Boot!
#   0x48000000 = kernel
#   -           = no ramdisk (OK for earlycon test)
#   0x4D000040  = DTB (at offset 0x40 inside DTBO image)
booti 0x48000000 - 0x4D000040
```

### Expected Results:
- **If earlycon output appears** → The overlapping memmove in normal boota
  flow is the root cause. Fix: modify kernel_addr in vendor_boot or change
  U-Boot relocation logic.
- **If still hangs** → Issue is NOT memmove. Proceed to Test 2/3.

---

## Test 2: Full Reflash All Images

Purpose: Ensure all partitions are correctly populated (including init_boot,
super, vbmeta). A partial flash may have left some partitions with stale
SRG-config data.

```bash
# ============================================
# Run on the Linux build host
# ============================================

# Step 1: Go to the build output directory
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build/out/target/product/evk_8mp

# Step 2: Verify all required images exist
ls -la boot.img vendor_boot.img init_boot.img dtbo-imx8mp.img \
       vbmeta-imx8mp.img u-boot-imx8mp.imx super.img partition-table.img

# Step 3: Identify SD card device (plug in SD card, check dmesg)
dmesg | tail -20
# Look for something like: [sdb] ... -> /dev/sdb

# Step 4: Full flash (DESTROYS ALL DATA on SD card!)
#   -f imx8mp  = i.MX8MP SoC (bootloader offset 32KB)
#   -a         = flash all partitions
#   -D .       = use images from current directory
#   /dev/sdX   = your SD card device (DOUBLE CHECK!)
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdX

# Step 5: Sync and safely eject
sync
sudo eject /dev/sdX
```

### After flashing:
1. Insert SD card into EVK
2. Power on, let autoboot run (`boota mmc1`)
3. Watch for kernel output after "Starting kernel ..."

---

## Test 3: Clean Rebuild Without Earlycon (100% Stock EVK)

Purpose: Rule out any build artifact contamination. Start from original
source files and do a completely clean build.

```bash
# ============================================
# Run on the Linux build host
# ============================================

# Step 1: Revert BoardConfig.mk to ORIGINAL (remove earlycon)
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build

# Check current state
diff device/nxp/imx8m/evk_8mp/BoardConfig.mk \
     ~/srg-imx8pl-android14-porting/original/device/nxp/imx8m/evk_8mp/BoardConfig.mk

# Copy original back
cp ~/srg-imx8pl-android14-porting/original/device/nxp/imx8m/evk_8mp/BoardConfig.mk \
   device/nxp/imx8m/evk_8mp/BoardConfig.mk

# Step 2: Verify gki_defconfig (BTF=n is needed for build, keep it)
grep "CONFIG_DEBUG_INFO_BTF" vendor/nxp-opensource/kernel_imx/arch/arm64/configs/gki_defconfig
# Should show: CONFIG_DEBUG_INFO_BTF=n

# Step 3: Set up build environment
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
export _JAVA_OPTIONS="-Xmx16g"
source build/envsetup.sh
lunch evk_8mp-trunk_staging-userdebug

# Step 4: Clean rebuild bootloader (ensures EVK config)
./imx-make.sh bootloader -j$(nproc)

# Step 5: Clean rebuild kernel images
./imx-make.sh bootimage -c -j$(nproc)
./imx-make.sh vendorbootimage -j$(nproc)
./imx-make.sh dtboimage -j$(nproc)

# Step 6: Rebuild vbmeta (must be after boot/vendor_boot/dtbo)
cd out/target/product/evk_8mp
make -C /mnt/data/imx-android-14.0.0_2.2.0/android_build vbmetaimage
# Or from build root:
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build
make vbmetaimage

# Step 7: Verify vbmeta was created properly
ls -la out/target/product/evk_8mp/vbmeta.img
# Copy to the expected filename
cp out/target/product/evk_8mp/vbmeta.img \
   out/target/product/evk_8mp/vbmeta-imx8mp.img

# Step 8: Full flash to SD card
cd out/target/product/evk_8mp
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdX
sync
```

### Notes:
- Without earlycon, the stock EVK has `console=ttynull` as the built-in
  kernel console. You will NOT see kernel log on serial console.
- If the board boots (shows Android boot animation on display, or adb
  becomes available), the kernel works — the hang was earlycon-related.
- If the board still hangs (no display activity, watchdog reset), the
  issue is NOT earlycon-related.

---

## Quick Reference: RDC Memory Regions (from ATF)

| Region | Address Range          | A53 Access | Note           |
|--------|----------------------|------------|----------------|
| 40     | 0x00000000-0x50000000 | R+W        | Normal DRAM    |
| 41     | 0x50000000-0x58000000 | **W only** | BL32/TEE area  |
| 42     | 0x58000000-0xFFFFFFFF | R+W        | Upper DRAM     |

**IMPORTANT**: Do NOT load kernel/DTB into 0x50000000-0x58000000!
