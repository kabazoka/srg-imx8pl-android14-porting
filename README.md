# SRG-iMX8PL Android 14 Porting Notes

**Date:** 2026-02-05 (Updated: 2026-02-24)
**Platform:** SRG-iMX8PL (based on NXP i.MX8MP EVK)
**OS:** Android 14

## Overview

This note documents the porting of Android 14 to the SRG-iMX8PL custom board, including RTC integration, 4GB DDR timing support, USB VBUS fix, serial console built-in driver, Kconfig dependency chain fix, UART4 DMA probe fix, and debugging multiple boot hang/freeze issues.

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
├── original/                 # 17 unmodified NXP BSP files
│   ├── vendor/nxp-opensource/
│   │   ├── uboot-imx/       # 7 files: DTS, DDR timing, config, fastboot
│   │   ├── kernel_imx/      # 5 files: DTS, Kconfig, clock driver, GKI
│   │   └── imx-mkimage/     # 1 file: pad_image.sh
│   └── device/nxp/          # 4 files: build scripts, board config
├── modified/                 # 17 SRG-modified files (same tree structure)
│   └── (same as original/)
├── reference/
│   ├── patches/              # AAEON vendor patches
│   ├── scripts/              # Flash script, apply-platform, etc.
│   └── notes/                # Vendor notes
├── README.md
└── CLAUDE.md

/mnt/data/unmodified_source/          # Moved binaries, flash-images, vendor-reference
/mnt/data/imx-android-14.0.0_2.2.0/android_build/  # Actual Android Build Tree
```

### Deploying Modifications
To apply SRG modifications to the Android build tree:

```bash
BUILD=/mnt/data/imx-android-14.0.0_2.2.0/android_build
for f in $(find ~/srg-imx8pl-android14-porting/modified -type f); do
  dest="$BUILD/${f#*modified/}"
  cp "$f" "$dest"
done
```

To restore original NXP files:
```bash
BUILD=/mnt/data/imx-android-14.0.0_2.2.0/android_build
for f in $(find ~/srg-imx8pl-android14-porting/original -type f); do
  dest="$BUILD/${f#*original/}"
  cp "$f" "$dest"
done
```

---

## Complete Modification Audit

All changes to the Android build tree vs unmodified NXP source (18 modifications across 5 repos):

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

### Repo 3: `vendor/nxp-opensource/kernel_imx/` (5 files)

| # | File | Change | Status |
|---|------|--------|--------|
| 9 | `arch/arm64/boot/dts/freescale/imx8mp-evk.dts` | UART4 + USB host + RTC + regulators + DMA delete-property | ✅ Correct |
| 10 | `arch/arm64/configs/gki_defconfig` | CONFIG_DEBUG_INFO_BTF=y→n | ✅ Build fix |
| 14 | `drivers/clk/imx/clk-imx8mp.c` | uart4 clock → `_critical` (prevent gate disable) | ✅ Boot hang fix |
| 16 | `arch/arm64/configs/imx8mp_gki.fragment` | SOC_IMX8M=m→y, SERIAL_IMX=m→y, SERIAL_IMX_CONSOLE=m→y, BUSFREQ=m→y | ✅ Console + busfreq built-in |
| 18 | `android/abi_gki_aarch64_imx` | Added `request_bus_freq`, `release_bus_freq`, `get_bus_freq_mode` to GKI allowlist | ✅ Protected symbol fix |

### Repo 4: `vendor/nxp-opensource/imx-mkimage/` (1 file)

| # | File | Change | Status |
|---|------|--------|--------|
| 11 | `scripts/pad_image.sh` | Skip missing tee.bin instead of error | ✅ Build fix for SPD=none |

### Repo 5: `vendor/nxp-opensource/uboot-imx/` — AVB Auto-Unlock (2026-02-23)

| # | File | Change | Status |
|---|------|--------|--------|
| 12 | `drivers/fastboot/fb_fsl/fb_fsl_boot.c` | Auto-unlock LOCKED device in `do_boota()` | ✅ Dev convenience |

### Repo 2 (additional): `device/nxp/` — Kernel cmdline & module list (2026-02-23)

| # | File | Change | Status |
|---|------|--------|--------|
| 13 | `imx8m/evk_8mp/BoardConfig.mk:134-135` | `keep_bootcon initcall_debug` + `androidboot.console=ttymxc3` | ✅ Fixed |
| 15 | `imx8m/evk_8mp/BoardConfig.mk:134` | Added `console=ttymxc3,115200` to kernel cmdline | ✅ Console input fix |
| 17 | `imx8m/evk_8mp/SharedBoardConfig.mk` | Removed `soc-imx8m.ko` + `busfreq-imx8mq.ko` + `imx.ko` from module list (now built-in) | ✅ Linker fix |

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

## Task 5: AVB Unlock & Boot Debug - In Progress (2026-02-23)

### Problem
After modifying `vendor_boot.img` (cmdline changes), AVB hash verification fails:
- `vendor_boot_a: Hash of data does not match digest in descriptor`
- Device state `LOCK` → refuses to boot
- U-Boot has no `avb` command, USB broken (`USB init failed: -22`) → can't `fastboot flashing unlock`

### Solution: Auto-Unlock in U-Boot
Added 5 lines to `fb_fsl_boot.c` in `do_boota()`, after lock status check:
```c
/* SRG: Auto-unlock for development */
if (lock_status == FASTBOOT_LOCK) {
    printf("SRG: Auto-unlocking device for development...\n");
    fastboot_set_lock_stat(FASTBOOT_UNLOCK);
    lock_status = FASTBOOT_UNLOCK;
    allow_fail = true;
}
```
- Persists to `fbmisc` partition — subsequent boots stay UNLOCKED
- No userdata wipe (preserves A/B metadata)
- AVB hash mismatch becomes warning, not fatal

### Also Fixed: BoardConfig.mk
```makefile
# Line 134-135
BOARD_KERNEL_CMDLINE := init=/init ... keep_bootcon initcall_debug
BOARD_BOOTCONFIG += androidboot.console=ttymxc3 androidboot.hardware=nxp
```
- `keep_bootcon`: prevents boot console de-registration (keeps earlycon alive)
- `initcall_debug`: logs every module init call for hang diagnosis
- cmdline goes into `vendor_boot.img` (NOT `boot.img`) — must use `./imx-make.sh vendorbootimage`

### Key Learnings

**Bootloader Image Selection:**
- `imx-make.sh bootloader` builds **7 variants** (defined in `UbootKernelBoardConfig.mk`)
- `imx-mkimage/iMX8M/flash.bin` = LAST variant = **UUU** (no `boota` command!)
- Correct image: `out/.../obj/UBOOT_COLLECTION/u-boot-imx8mp.imx`

**A/B Slot Metadata:**
- Stored in misc partition (ptn 9 = `/dev/sdc9`) at offset 2048 bytes
- After 7 failed boots, `tries_remaining=0` → both slots unbootable → `get_curr_slot()=-1` → OOB array access → "boot header version not supported"
- Fix: write valid `bootloader_control` struct with priority=15, tries=7

### Boot Progress (2026-02-23)
```
SRG: Auto-unlocking device for development...   ✅ AVB auto-unlock
verify FAIL, state: UNLOCK                      ✅ Continues despite hash mismatch
boot 'boot_a' still                             ✅ Slot A selected
Starting kernel ...                             ✅ Kernel loading
earlycon: ec_imx6q0 at MMIO 0x30a60000         ✅ UART4 earlycon
keep_bootcon + initcall_debug in cmdline        ✅ Debug flags active
init: init first stage started!                 ✅ Android init running
init: Loading module mxc-clk.ko                 ✅ Module loading in progress
```

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

| 指令 | 做什麼 | 產出 |
|------|--------|------|
| `./imx-make.sh bootloader -j$(nproc)` | 編譯 SPL + ATF + U-Boot（7 個 variant） | `u-boot-imx8mp.imx` |
| `./imx-make.sh bootimage -j$(nproc)` | 編譯 kernel + 打包 boot.img | `boot.img` |
| `./imx-make.sh vendorbootimage -j$(nproc)` | 編譯 modules + DTB + 打包 vendor_boot.img | `vendor_boot.img` |
| `./imx-make.sh -c bootimage -j$(nproc)` | **先 `make clean`** 再編譯（強制重新編譯） | `boot.img` |

> **WARNING**: `imx-mkimage/iMX8M/flash.bin` = 最後一個 variant = **UUU**（沒有 `boota`！）
> 正確的 U-Boot image: `out/.../obj/UBOOT_COLLECTION/u-boot-imx8mp.imx`

> **WARNING: GKI boot.img 陷阱（切回 EVK 時務必注意）**
> NXP 原版 `imx-make.sh` 預設 `ENABLE_GKI=1`（Line 83: `enable_gki=${ENABLE_GKI:-1}`）。
> 當 `enable_gki=1` 時，`./imx-make.sh bootimage` 會：
> 1. 先用 **imx kernel** build `boot.img`
> 2. 把它改名為 `boot-imx.img`
> 3. 再用 **GKI kernel**（Google 通用版，35MB）重新 build `boot.img`
>
> 結果：`boot.img` = GKI kernel（缺少 i.MX8MP driver），`boot-imx.img` = imx kernel（正確的）。
> 如果燒 `boot.img` → kernel 在 "Starting kernel ..." 後直接 panic reboot。
>
> **SRG modified 版本**已改為 `ENABLE_GKI=0`（修改 #7），不會有此問題。
> **切回 EVK 原版時**，必須用 `ENABLE_GKI=0 ./imx-make.sh bootimage -j$(nproc)`，
> 或者 flash 時用 `boot-imx.img` 而非 `boot.img`。

### Image Content Summary

| Image | Contains | SD Card Partition |
|-------|----------|-------------------|
| `boot.img` | Kernel binary (`Image.gz`) | `/dev/sdc3` |
| `vendor_boot.img` | cmdline + kernel modules (`.ko`) + DTB + vendor ramdisk | `/dev/sdc7` |
| `u-boot-imx8mp.imx` | SPL + ATF + U-Boot | `/dev/sdc` (seek=32k) |

> **CRITICAL**: Kernel modules 和 DTB 都在 `vendor_boot.img` 裡，**不是** `boot.img`！
> - `boot.img` 只有 kernel binary
> - cmdline 也在 `vendor_boot.img`（因為 `BOARD_BOOT_HEADER_VERSION=4` + `TARGET_USE_VENDOR_BOOT=true`）
> - 改了任何 kernel source → 必須 rebuild **兩個** image 再 flash

### Incremental Build 的陷阱

NXP build system 用 make 的 incremental build（`.cmd` 檔 + timestamp）偵測源碼變更。
**已知問題：有時改了 .dts 或 .c 檔後 make 不會重新編譯！**

**症狀：** build 成功但 flash 後行為沒改變（DTB/Image 的 timestamp 是幾天前的）

**解法：用 `-c` flag 強制 clean build**
```bash
# 推薦方式：-c = make clean + 重新編譯（保證所有改動都編譯進去）
./imx-make.sh -c bootimage -j$(nproc) && ./imx-make.sh vendorbootimage -j$(nproc)
```

**Build 後驗證（flash 前必做）：**
```bash
# 確認 DTB 和 Image 時間戳是「剛剛」
ls -la out/target/product/evk_8mp/obj/KERNEL_OBJ/arch/arm64/boot/dts/freescale/imx8mp-evk.dtb
ls -la out/target/product/evk_8mp/obj/KERNEL_OBJ/arch/arm64/boot/Image*

# 確認 .config 關鍵設定
grep CONFIG_SOC_IMX8M= out/target/product/evk_8mp/obj/KERNEL_OBJ/.config
grep CONFIG_IMX8M_BUSFREQ= out/target/product/evk_8mp/obj/KERNEL_OBJ/.config
grep CONFIG_SERIAL_IMX= out/target/product/evk_8mp/obj/KERNEL_OBJ/.config
# 三個都應該是 =y
```

### Force Module Rebuild（針對單一模組的替代方案）
如果只改了一個 .c 檔，可以不用 `-c` clean，改為手動刪除該模組的 cache：
```bash
# 以 clk-imx8mp.ko 為例
rm -f out/target/product/evk_8mp/obj/KERNEL_OBJ/drivers/clk/imx/clk-imx8mp.ko
rm -f out/target/product/evk_8mp/obj/KERNEL_OBJ/drivers/clk/imx/clk-imx8mp.mod*
rm -f out/target/product/evk_8mp/obj/KERNEL_OBJ/drivers/clk/imx/.clk-imx8mp*.cmd
# 也刪除 vendor_ramdisk 和 packaging 中的 cache
rm -f out/target/product/evk_8mp/vendor_ramdisk/lib/modules/clk-imx8mp.ko
rm -f out/target/product/evk_8mp/obj/PACKAGING/depmod_VENDOR_RAMDISK_intermediates/lib/modules/0.0/lib/modules/clk-imx8mp.ko
rm -f out/target/product/evk_8mp/obj/PACKAGING/depmod_vendor_ramdisk_stripped_intermediates/clk-imx8mp.ko

# 然後 rebuild（不需 -c）
./imx-make.sh bootimage -j$(nproc) && ./imx-make.sh vendorbootimage -j$(nproc)
```

### Flash to eMMC（UUU）

> **注意：UUU 燒錄的所有 image 必須來自同一次 build！**
> 如果 `super.img`（2月27）和 `vbmeta`（3月2）時間戳不同，dm-verity 會判定 system partition corrupted → reboot loop。
> 燒之前先確認：`ls -lh out/target/product/evk_8mp/{super.img,vbmeta-imx8mp.img,boot.img,vendor_boot.img}`

```bash
cd out/target/product/evk_8mp

# GKI 陷阱：clean imx-make.sh 預設 ENABLE_GKI=1，boot.img 會是 GKI kernel（35MB）
# imx kernel 被改名為 boot-imx.img（14MB）。燒之前務必確認：
ls -lh boot.img boot-imx.img
# 如果 boot.img 是 35MB → 先覆蓋：
cp boot-imx.img boot.img

# 燒 eMMC（EVK 用 USB-C 連接 PC，撥到 download mode）
sudo ./uuu_imx_android_flash.sh -f imx8mp -e
```

### Flash to SD Card

```bash
# === 方式 A：只更新 kernel（最常用） ===
sudo dd if=out/target/product/evk_8mp/boot.img of=/dev/sdc3 bs=10M conv=fsync,nocreat
sudo dd if=out/target/product/evk_8mp/vendor_boot.img of=/dev/sdc7 bs=10M conv=fsync,nocreat
sync

# === 方式 B：也更新 U-Boot ===
sudo dd if=out/target/product/evk_8mp/obj/UBOOT_COLLECTION/u-boot-imx8mp.imx of=/dev/sdc bs=1k seek=32 conv=fsync,nocreat
sudo dd if=out/target/product/evk_8mp/boot.img of=/dev/sdc3 bs=10M conv=fsync,nocreat
sudo dd if=out/target/product/evk_8mp/vendor_boot.img of=/dev/sdc7 bs=10M conv=fsync,nocreat
sync

# === 方式 C：全部重新 flash（partition + system） ===
cd /mnt/data/unmodified_source/flash-images/srg
sudo ~/srg-imx8pl-android14-porting/reference/scripts/imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdX
# 注意：full flash 後 ALWAYS 手動 dd boot.img + vendor_boot.img（flash script 可能不會寫入）
sudo dd if=out/target/product/evk_8mp/boot.img of=/dev/sdc3 bs=10M conv=fsync,nocreat
sudo dd if=out/target/product/evk_8mp/vendor_boot.img of=/dev/sdc7 bs=10M conv=fsync,nocreat
sync
```

### A/B Metadata 重置（如果 boot 失敗 7 次後無法開機）

**症狀：** U-Boot 報 `get_curr_slot()=-1` 或 `boot header version not supported`

**原因：** misc partition（`/dev/sdc9`）offset 2048 的 `bootloader_control` struct，`tries_remaining` 每次失敗 -1，降到 0 後兩個 slot 都不可開機。

```bash
sudo python3 -c "
import struct, zlib
slot=bytes([0x7F,0x00])  # priority=127, tries_remaining=0 (successful)
data=(b'_a\x00\x00'      # slot_suffix='_a'
     +struct.pack('<I',0x42414342)  # magic='BACB'
     +bytes([1,2])        # version=1, nb_slot=2
     +b'\x00\x00'         # recovery_tries_remaining=0, merge_status=0
     +slot+slot            # slot_info[0], slot_info[1]
     +b'\x00'*4           # reserved0
     +b'\x00'*8)          # reserved1
full=data+struct.pack('<I',zlib.crc32(data)&0xFFFFFFFF)  # append CRC32
f=open('/dev/sdc9','r+b'); f.seek(2048); f.write(full); f.flush()
print('OK:', full.hex())
" && sync
```

### Copy Build Artifacts（備份）
```bash
# Build artifacts are now stored at /mnt/data/unmodified_source/flash-images/
cp /mnt/data/imx-android-14.0.0_2.2.0/android_build/out/target/product/evk_8mp/obj/UBOOT_COLLECTION/u-boot-imx8mp.imx \
   /mnt/data/unmodified_source/flash-images/srg/u-boot-imx8mp.imx
```

---

## Task 6: Kernel Clock Module Hang — Fixed (2026-02-23)

### Problem
System hangs at `clk-imx8mp.ko` module loading during Android init first stage. No UART output, no HDMI — confirmed hard kernel hang.

### Root Cause
`__imx8m_clk_hw_composite()` in `clk-composite-8m.c:311-317` **disables the clock gate (bit 28)** for non-`CLK_IS_CRITICAL` clocks during registration:

```c
if (!(flags & CLK_IS_CRITICAL) && !(mcore_booted && m4_lpa_required(name))) {
    val = readl(reg);
    val &= ~BIT(PCG_CGC_SHIFT);  // clear bit 28
    writel(val, reg);              // UART4 clock DISABLED!
}
```

- UART4 (SRG console) was registered as `imx8m_clk_hw_composite()` (non-critical)
- Gate bit cleared → UART4 hardware clock stopped
- earlycon TX polling (`while(!(readl(USR2) & TXDC))`) waits forever → **hard hang**
- EVK unaffected: uart2 (EVK console) uses `_critical` variant, gate not cleared

### Fix
**File:** `vendor/nxp-opensource/kernel_imx/drivers/clk/imx/clk-imx8mp.c`

```c
// Before (hangs on SRG):
hws[IMX8MP_CLK_UART4] = imx8m_clk_hw_composite("uart4", imx8mp_uart4_sels, ccm_base + 0xb080);

// After (fixed):
hws[IMX8MP_CLK_UART4] = imx8m_clk_hw_composite_critical("uart4", imx8mp_uart4_sels, ccm_base + 0xb080);
```

### Debug Method
Binary search with `pr_err()` checkpoints in the probe function — 5 iterations to narrow from ~300 clock registrations to the exact uart4 line.

---

## Task 7: Serial Console Input Fix (2026-02-23) — ✅ Verified (2026-02-24)

### Problem
After clk-imx8mp.ko fix, Android boots to HDMI (lock screen visible). But serial console (UART4) only shows output — keyboard input not accepted.

### Root Cause (Two Issues)

**Issue 1:** Kernel cmdline missing `console=ttymxc3,115200`
- earlycon provides TX-only output (write-only, no RX interrupt)
- `androidboot.console=ttymxc3` only tells Android init which TTY to use — doesn't register kernel TTY

**Issue 2:** `CONFIG_SERIAL_IMX=m` (module, not built-in)
- `imx8mp_gki.fragment` (line 13-14) sets `CONFIG_SERIAL_IMX=m` and `CONFIG_SERIAL_IMX_CONSOLE=m`
- This fragment is applied LAST in kernel config merge, overriding `gki_defconfig`'s `=y`
- Config merge order: `gki_defconfig` → `imx8mp_gki.fragment` (last wins)
- With modular driver, `console=ttymxc3,115200` deferred registration may not work properly

### Fix (Two Files)

1. **`device/nxp/imx8m/evk_8mp/BoardConfig.mk`** (line 134)
   - Added `console=ttymxc3,115200` to `BOARD_KERNEL_CMDLINE`

2. **`vendor/nxp-opensource/kernel_imx/arch/arm64/configs/imx8mp_gki.fragment`** (line 13-14)
   - Changed `CONFIG_SERIAL_IMX=m` → `=y`
   - Changed `CONFIG_SERIAL_IMX_CONSOLE=m` → `=y`
   - Makes imx-uart driver built-in → console registered at kernel boot

### Linker Error: `request_bus_freq` undefined

Changing `SERIAL_IMX=y` causes linker error because `imx.c:1376` calls `request_bus_freq()`/`release_bus_freq()` from `busfreq-imx8mq.ko` (still =m). Built-in code cannot link against module symbols.

**Fix chain (3 files):**
1. `imx8mp_gki.fragment`: `CONFIG_IMX8M_BUSFREQ=m` → `=y`
2. `SharedBoardConfig.mk`: remove `busfreq-imx8mq.ko` + `imx.ko`（built-in = 不產生 .ko）

**Kconfig 降級陷阱：**
但 `CONFIG_IMX8M_BUSFREQ=y` 會被 Kconfig 自動降級為 `=m`！原因：
```
# imx8mp_gki.fragment
CONFIG_SOC_IMX8M=m        ← BUSFREQ depends on 這個
CONFIG_IMX8M_BUSFREQ=y    ← 想要 built-in
```
Kconfig 規則：**built-in 不能依賴 module** → `BUSFREQ=y` 自動降為 `=m`。

**最終完整 fix：**
```diff
# imx8mp_gki.fragment
-CONFIG_SOC_IMX8M=m
+CONFIG_SOC_IMX8M=y
 CONFIG_SERIAL_IMX=y
 CONFIG_SERIAL_IMX_CONSOLE=y
 CONFIG_IMX8M_BUSFREQ=y
```
- `SOC_IMX8M=y` → `soc-imx8m.ko` 變 built-in → 也要從 SharedBoardConfig.mk 移除
- 其他依賴 `SOC_IMX8M` 的 module（如 `imx8m_pm_domains.ko`、`pinctrl-imx8mp.ko`）不受影響（module 可依賴 built-in）

**SharedBoardConfig.mk 共移除 3 個 .ko：**
- `soc-imx8m.ko`（SOC_IMX8M=y）
- `busfreq-imx8mq.ko`（IMX8M_BUSFREQ=y）
- `imx.ko`（SERIAL_IMX=y）

### Current Status (2026-02-24) — ✅ Verified
- HDMI: Android lock screen visible, time updating (system alive)
- Serial console 輸出: ✅ 正常（earlycon + ttymxc3）
- Serial console 輸入: ✅ 正常（shell prompt 可操作）
- Kernel: `6.6.36-4k-g112aa92f1762-dirty`
- ttymxc3 probe: ✅ `30a60000.serial: ttymxc3 at MMIO 0x30a60000`
- `console [ttymxc3] enabled`: ✅ 確認

---

## Task 8: USB Fix — AAEON Patch Reference (2026-02-23)

### Problem
USB mouse/keyboard 插上去沒反應，ADB over USB 也不行。

### Root Cause
對比 AAEON 官方 kernel patch (`patches/001-srg-imx8pl-kernel-all.patch`) 發現多處差異：

| 項目 | 修改前（錯誤） | 修改後（正確） | 影響 |
|------|---------------|---------------|------|
| VBUS regulator 極性 | `enable-active-high` | `enable-active-low` | **USB 完全沒電！** |
| VBUS pad value | `0x10` | `0x59` | GPIO 驅動能力不足 |
| USB-A connector 子節點 | 缺少 | 已加入 | USB framework metadata |
| EVK `reg_usb_vbus` (GPIO1_14) | 存在 | 已刪除 | SRG 不使用 |

**關鍵問題**：SRG 用 P-channel MOSFET 控制 VBUS，`enable-active-low` = GPIO LOW 才通電。原本設定 `enable-active-high` → regulator enable 時 GPIO 拉 HIGH → MOSFET OFF → USB 裝置完全沒電。

### Fix
**File:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts`

1. **VBUS 極性修正** — `reg_usb1_vbus` & `reg_usb2_vbus`:
   - `enable-active-high` → `enable-active-low`
   - 新增 `startup-delay-us = <100000>` (100ms 啟動延遲)

2. **Pad value** — `pinctrl_usb1_vbus` & `pinctrl_usb2_vbus`:
   - `0x10` → `0x59` (higher drive + pull config)

3. **USB-A connector** — `&usb3_0` & `&usb3_1`:
   ```dts
   connector {
       compatible = "usb-a-connector";
       vbus-supply = <&reg_usb1_vbus>;  /* or reg_usb2_vbus */
   };
   ```

4. **移除 EVK `reg_usb_vbus`** (GPIO1_IO14, SRG 不使用)

---

## Task 10: GKI Protected Symbol — sdhci Reboot Loop (2026-02-24) — ✅ Verified

### Problem
Clean rebuild 後改動生效（clk hang 修好、blk-ctrl 正常），但開機進入 reboot loop。

Log 關鍵行：
```
sdhci_esdhc_imx: Protected symbol: request_bus_freq (err -13)
sdhci_esdhc_imx: Protected symbol: release_bus_freq (err -13)
```
sdhci 是 SD/eMMC 驅動 → 載入失敗 → init 無法 mount system partition → kernel panic → reboot。

### Root Cause: GKI Protected Symbol 機制

Android GKI kernel（`kernel/module/main.c:1154-1170`）對 vendor module（未簽名 .ko）有 symbol 存取保護：
1. Module 載入時每個引用的 symbol 都要檢查
2. 如果 symbol 在 vmlinux（built-in），必須在 `abi_gki_aarch64_imx` allowlist 裡才允許
3. Module 之間（.ko → .ko）的 symbol 存取不受此限制

原本 BUSFREQ=m → `request_bus_freq`/`release_bus_freq` 在 `busfreq-imx8mq.ko`（module）→ sdhci.ko 可自由存取。
改成 BUSFREQ=y → symbol 在 vmlinux → 不在 allowlist → **-EACCES (err -13)**。

影響範圍：31 個 driver 用了 busfreq API（sdhci、USB dwc3、ethernet、crypto 等）。

### Fix
**File:** `vendor/nxp-opensource/kernel_imx/android/abi_gki_aarch64_imx`

在 GKI symbol allowlist 加入 3 個 symbol（按字母順序）：
```
  get_bus_freq_mode     ← 插在 get_cached_msi_msg 前
  release_bus_freq      ← 插在 release_firmware 前
  request_bus_freq      ← 插在 request_firmware 前
```

### GKI Protected Symbol 機制說明

```
Vendor module (.ko, 未簽名) 載入時：
  resolve_symbol(name) →
    if symbol 在其他 vendor module → ✅ 允許
    if symbol 在 abi_gki_aarch64_imx allowlist → ✅ 允許
    else → ❌ -EACCES "Protected symbol"
```

此機制防止 vendor module 依賴非穩定的 kernel ABI。但 NXP 原本 BUSFREQ 是 module，不需要加到 allowlist；
我們改成 built-in 後就需要了。

---

## Task 11: UART4 Serial Console Input — DMA Probe 衝突 (2026-02-24) — ✅ Verified

### Problem
GKI fix 後 Android 正常開機（HDMI lock screen），但 serial console 仍無法輸入。
Boot log 顯示 ttymxc0/1/2 都成功 probe，唯獨 **ttymxc3（UART4）缺失**。

### Root Cause
DTSI（`imx8mp.dtsi:1199-1209`）為 uart4 定義了 DMA 通道：
```dts
dmas = <&sdma1 28 4 0>, <&sdma1 29 4 0>;
dma-names = "rx", "tx";
```

當 earlycon 佔用 UART4（直接寫 register 做 TX），imx-uart driver probe 時若啟用 DMA 會衝突 → **probe 靜默失敗** → ttymxc3 不註冊 → 只剩 earlycon 的 TX-only 輸出。

EVK 不受影響：EVK 的 earlycon 在 uart2，uart4 沒被佔用所以 DMA probe 不會衝突。

AAEON 官方 kernel patch（`patches/001-srg-imx8pl-kernel-all.patch` line 802-808）有此修正。

### Fix
**File:** `vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts`

```dts
&uart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    /delete-property/ dmas;
    /delete-property/ dma-names;
    status = "okay";
};
```

`/delete-property/` 覆蓋 DTSI 的 DMA 設定，強制 uart4 使用 PIO（programmed I/O）模式，避免與 earlycon 衝突。

> **Note:** AAEON patch 有 typo `dmas-names`，正確 property name 是 `dma-names`（無 s）。

### 驗證結果 (2026-02-24) — ✅ Confirmed
```
evk_8mp:/ # dmesg | grep ttymxc
[    6.969616] 30890000.serial: ttymxc1 at MMIO 0x30890000 (irq = 17, base_baud = 1500000) is a IMX
[    6.977848] 30a60000.serial: ttymxc3 at MMIO 0x30a60000 (irq = 18, base_baud = 1500000) is a IMX
[    6.995519] printk: console [ttymxc3] enabled
[    7.006982] 30860000.serial: ttymxc0 at MMIO 0x30860000 (irq = 55, base_baud = 5000000) is a IMX
[    7.007950] 30880000.serial: ttymxc2 at MMIO 0x30880000 (irq = 56, base_baud = 5000000) is a IMX

evk_8mp:/ # uname -r
6.6.36-4k-g112aa92f1762-dirty
```
- ttymxc0~3 四個 UART 全部成功 probe ✅
- `console [ttymxc3] enabled` 確認 UART4 為 kernel console ✅
- Serial console 輸入正常（shell prompt 可操作）✅

---

## Task 9: Build Not Taking Effect — Stale DTB/Image (2026-02-23)

### Problem
完成所有源碼改動（USB DTS + SERIAL_IMX=y + BUSFREQ=y）後 rebuild + flash，但**改動完全無效** — USB 和 Serial console 都沒改善。

### Root Cause 1: Build 用了舊的 cached binary

| 檔案 | 時間戳 | 問題 |
|------|--------|------|
| 源碼 `imx8mp-evk.dts` | Feb 23 17:20 | 剛改 |
| 編譯的 `imx8mp-evk.dtb` | **Feb 9 18:00** | **14天前！** |
| Kernel `Image` | **Feb 6 17:06** | **17天前！** |
| `boot.img` | Feb 23 16:53 | 在源碼改動之前就 build 了 |
| `vendor_boot.img` | Feb 23 16:55 | 同上 |

`./imx-make.sh bootimage` 會觸發 kernel 編譯，但 make 的 incremental build 機制（`.cmd` 檔案 + timestamp）沒偵測到 DTS/source 變更，所以**跳過了重新編譯**，直接把舊的 DTB 和 Image 打包進 boot.img/vendor_boot.img。

### Root Cause 2: Kconfig 降級（CONFIG_IMX8M_BUSFREQ=y → =m）

Fragment 已設 `CONFIG_IMX8M_BUSFREQ=y`，但實際 `.config` 仍是 `=m`：
- 原因：`CONFIG_SOC_IMX8M=m`（module），而 BUSFREQ `depends on SOC_IMX8M`
- Kconfig 規則：built-in 不能依賴 module → 自動降級為 `=m`
- 修正：`CONFIG_SOC_IMX8M=m` → `=y`（見 Task 7 完整說明）

### Fix: 強制 Clean Rebuild

```bash
cd /mnt/data/imx-android-14.0.0_2.2.0/android_build

# -c flag = make clean 再編譯（刪除所有 .o/.ko/.dtb，從頭編譯）
./imx-make.sh -c bootimage -j$(nproc) && ./imx-make.sh vendorbootimage -j$(nproc)
```

### Build 後驗證（flash 前必做）

```bash
# 1. 確認 DTB 和 Image 時間戳是「剛剛」（不是幾天前）
ls -la out/target/product/evk_8mp/obj/KERNEL_OBJ/arch/arm64/boot/dts/freescale/imx8mp-evk.dtb
ls -la out/target/product/evk_8mp/obj/KERNEL_OBJ/arch/arm64/boot/Image*

# 2. 確認 .config 裡的關鍵設定
grep CONFIG_IMX8M_BUSFREQ out/target/product/evk_8mp/obj/KERNEL_OBJ/.config
# 預期：CONFIG_IMX8M_BUSFREQ=y

grep CONFIG_SOC_IMX8M out/target/product/evk_8mp/obj/KERNEL_OBJ/.config
# 預期：CONFIG_SOC_IMX8M=y

grep CONFIG_SERIAL_IMX= out/target/product/evk_8mp/obj/KERNEL_OBJ/.config
# 預期：CONFIG_SERIAL_IMX=y

# 3. 確認移除的 .ko 不存在
ls out/target/product/evk_8mp/obj/KERNEL_OBJ/drivers/soc/imx/soc-imx8m.ko 2>&1
ls out/target/product/evk_8mp/obj/KERNEL_OBJ/drivers/soc/imx/busfreq-imx8mq.ko 2>&1
ls out/target/product/evk_8mp/obj/KERNEL_OBJ/drivers/tty/serial/imx.ko 2>&1
# 預期：全部 No such file（因為是 built-in，不產生 .ko）
```

### imx-make.sh Build 機制說明

| 指令 | 做什麼 | 會重新編譯嗎？ |
|------|--------|---------------|
| `./imx-make.sh bootimage` | 編譯 kernel + 打包 boot.img | 是，但 incremental（可能跳過） |
| `./imx-make.sh vendorbootimage` | 編譯 modules + DTB + 打包 vendor_boot.img | 是，但 incremental |
| `./imx-make.sh -c bootimage` | **先 `make clean`** 再編譯 + 打包 | **是，強制從頭** |
| `./imx-make.sh kernel` | 只編譯 kernel（不打包 .img） | incremental |
| `./imx-make.sh -c kernel` | clean + 重新編譯 kernel | **強制從頭** |

> **教訓：改了 DTS 或 .c 原始碼後，如果 incremental build 沒偵測到變更，必須用 `-c` flag 強制 clean build！**

---

## Flash & 驗證 SOP

### 1. Flash（build 完成後）

```bash
# boot.img → /dev/sdc3
sudo dd if=out/target/product/evk_8mp/boot.img of=/dev/sdc3 bs=10M conv=fsync,nocreat

# vendor_boot.img → /dev/sdc7
sudo dd if=out/target/product/evk_8mp/vendor_boot.img of=/dev/sdc7 bs=10M conv=fsync,nocreat

sync
```

### 2. 重置 A/B Metadata（如果之前已 7 次失敗 boot）

A/B metadata 在 misc partition（`/dev/sdc9`）offset 2048 bytes。
每次 boot 失敗 `tries_remaining` 會 -1，降到 0 後兩個 slot 都不可開機 → U-Boot 報錯 `get_curr_slot()=-1`。

```bash
sudo python3 -c "
import struct, zlib
slot=bytes([0x7F,0x00])  # priority=127, tries_remaining=0 (successful)
data=(b'_a\x00\x00'      # slot_suffix='_a'
     +struct.pack('<I',0x42414342)  # magic='BACB'
     +bytes([1,2])        # version=1, nb_slot=2
     +b'\x00\x00'         # recovery_tries_remaining=0, merge_status=0
     +slot+slot            # slot_info[0], slot_info[1]
     +b'\x00'*4           # reserved0
     +b'\x00'*8)          # reserved1
full=data+struct.pack('<I',zlib.crc32(data)&0xFFFFFFFF)  # append CRC32
f=open('/dev/sdc9','r+b'); f.seek(2048); f.write(full); f.flush()
print('OK:', full.hex())
" && sync
```

**欄位說明：**
- `slot_suffix='_a'`：目前使用 slot A
- `priority=0x7F (127)`：最高優先
- `tries_remaining=0x00`：0 = 已標記為 successful（不會 countdown）
- `magic=0x42414342 ('BACB')`：bootloader_control magic number
- CRC32 在最後 4 bytes，用 `zlib.crc32()` 計算

### 3. 驗證（開機後）

| 項目 | 預期結果 | 驗證方式 |
|------|---------|---------|
| Serial console 輸出 | 看到 boot log | minicom/picocom 連接 UART4 |
| Serial console 輸入 | 能打字、shell prompt | 按 Enter，應出現 `console:/ $` |
| USB 滑鼠 | HDMI 畫面出現游標 | 插入 USB 滑鼠 |
| USB 鍵盤 | 能操作 UI | 插入 USB 鍵盤 |
| Android Home Screen | 解鎖後看到桌面 | 用 USB 鍵盤/滑鼠解鎖 |

Serial console 進一步驗證：
```bash
# 在 serial console 上執行
dmesg | grep -i usb    # 應看到 USB device enumeration
dmesg | grep -i vbus   # 應看到 VBUS regulator enabled
dmesg | grep -i ttymxc # 應看到 console [ttymxc3] enabled
cat /proc/cmdline      # 應包含 console=ttymxc3,115200
```

---

## Project Status: ✅ Android 14 Confirmed Working (2026-02-24)

**Android 14 已在 SRG-iMX8PL 上成功運行。**

### 驗證結果
| 項目 | 狀態 | 備註 |
|------|------|------|
| DDR 4GB | ✅ | SPL 偵測 3G+1G 正確 |
| U-Boot console (UART4) | ✅ | `ttymxc3`, 115200 baud |
| Kernel boot | ✅ | `6.6.36-4k-g112aa92f1762-dirty` |
| Serial console 輸出 | ✅ | earlycon + ttymxc3 |
| Serial console 輸入 | ✅ | shell prompt 可操作 |
| HDMI 顯示 | ✅ | Android lock screen |
| Android OS | ✅ | Android 14 |
| ttymxc0~3 全部 probe | ✅ | 4 個 UART 全部註冊 |

### 已解決的所有問題（按時間順序）

**Phase 1: 硬體基礎**
- [x] 4GB DDR timing（meta-aaeon-nxp 官方 patch）
- [x] U-Boot UART4 migration（imx8mp_evk.h + DTS + SPL DTSI + imx8mp_evk.c）
- [x] ATF UART4 console（`IMX_BOOT_UART_BASE=0x30A60000`）
- [x] TEE/SPD fix（`SPD=none` + `pad_image.sh` skip tee.bin）
- [x] `CONFIG_BOOTCOMMAND="boota"`（無 saved env 時需要）

**Phase 2: Kernel 啟動**
- [x] RTC PCF85063ATL @ I2C3 0x51
- [x] USB host mode + VBUS regulators（GPIO1_05/06）
- [x] AVB auto-unlock for development（`fb_fsl_boot.c`）
- [x] `keep_bootcon initcall_debug` cmdline（debug 用）
- [x] `console=ttymxc3,115200` 加入 kernel cmdline
- [x] `androidboot.console=ttymxc3` 加入 BoardConfig.mk

**Phase 3: Clock / Module 修復**
- [x] clk-imx8mp.ko hang — uart4 clock gate 被 disable（→ `_critical` variant）
- [x] `CONFIG_SERIAL_IMX=m→y`（built-in console driver）
- [x] `CONFIG_IMX8M_BUSFREQ=m→y`（linker: `request_bus_freq` undefined）
- [x] `CONFIG_SOC_IMX8M=m→y`（Kconfig 降級陷阱：built-in 不能依賴 module）
- [x] 移除 3 個 .ko from SharedBoardConfig.mk（`soc-imx8m.ko` + `busfreq-imx8mq.ko` + `imx.ko`）

**Phase 4: GKI / DMA 修復**
- [x] GKI Protected Symbol — `abi_gki_aarch64_imx` 加入 3 個 busfreq symbol
- [x] UART4 DMA probe 衝突 — `/delete-property/ dmas` + `/delete-property/ dma-names`

**Phase 5: USB 硬體修復**
- [x] VBUS 極性（`enable-active-high` → `enable-active-low`，P-channel MOSFET）
- [x] Pad value（`0x10` → `0x59`）
- [x] USB-A connector 子節點
- [x] 移除 EVK `reg_usb_vbus`（GPIO1_14，SRG 不使用）

---

## FRDM-iMX8MP Porting

FRDM-iMX8MP 是 NXP 另一款 i.MX8MP 開發板，需要額外 patch 支援。

**詳細文件：** [`reference/notes/FRDM_patch_note.md`](reference/notes/FRDM_patch_note.md)

### Patch 檔案位置

```
reference/patches/frdm8mp_android14_patch/
├── device_nxp/    (1 patch)   → device/nxp
├── vendor/uboot/  (3 patches) → vendor/nxp-opensource/uboot-imx
├── vendor/kernel/ (11 patches)→ vendor/nxp-opensource/kernel_imx
└── vendor/mkimage/(1 patch)   → vendor/nxp-opensource/imx-mkimage
```

### 快速 Apply

```bash
BUILD=/mnt/data/imx-android-14.0.0_2.2.0/android_build
PATCHES=~/srg-imx8pl-android14-porting/reference/patches/frdm8mp_android14_patch

cd ${BUILD}/device/nxp && git apply ${PATCHES}/device_nxp/*.patch
cd ${BUILD}/vendor/nxp-opensource/uboot-imx && git am ${PATCHES}/vendor/uboot/*.patch
cd ${BUILD}/vendor/nxp-opensource/kernel_imx && git am --3way ${PATCHES}/vendor/kernel/*.patch
cd ${BUILD}/vendor/nxp-opensource/imx-mkimage && git am ${PATCHES}/vendor/mkimage/*.patch
```

> **注意：** kernel patch 必須用 `--3way`，因為 GKI symbol patch 的 context 是基於 2.1.0，在 2.2.0 上需要 3-way merge。

### Build & Flash

```bash
source build/envsetup.sh
lunch frdm_8mp-trunk_staging-userdebug
./imx-make.sh -j$(nproc)

# Flash（確認 boot.img 是 imx kernel，不是 GKI）
cd out/target/product/frdm_8mp
ls -lh boot.img boot-imx.img   # boot.img 應 ~14MB，若 35MB 則 cp boot-imx.img boot.img
sudo ./uuu_imx_android_flash.sh -f imx8mp -p frdm -a -e
```

---

### 未驗證 / 未來工作
- [ ] USB 滑鼠/鍵盤（DTS 已修正 VBUS 極性，待實機驗證）
- [ ] ADB over USB
- [ ] WiFi（8852BE driver — 需 GKI symbol list 更新 + PCIe patch）
- [ ] Bluetooth（rtk_btusb.ko）
- [ ] RS485（imx.c 修改 + GPIO mode 設定）
- [ ] LVDS 面板支援
- [ ] 量產 image 打包（OTA、emmc 燒錄）

### 已知限制
- Trusty modules (#5-8) — `SPD=none` 但 module 仍被載入（error but no hang）
- Kernel version 標記 `-dirty`（build tree 有未 commit 的改動，正常）
- `clk_ignore_unused` 仍在 cmdline（移除可能觸發其他 clock gate 問題）
