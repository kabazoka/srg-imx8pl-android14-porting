# FRDM-iMX8MP Android 14 Porting

**日期：** 2026-03-03
**平台：** FRDM-iMX8MP（NXP 官方開發板，不同於 EVK）
**OS：** Android 14 (imx-android-14.0.0_2.2.0)

---

## 概述

將 Android 14 部署到 FRDM-iMX8MP 開發板。FRDM 是 NXP 推出的另一款 i.MX8MP 開發板（不同於 EVK），需要額外的 patch 支援。

## Patch 來源與檔案位置

Patch 檔案位於本 repo：
```
reference/patches/frdm8mp_android14_patch/
├── device_nxp/
│   └── 0001-device-nxp-add-FRDM-i.MX8MP-Android14-basic-support.patch   # device config
├── vendor/
│   ├── uboot/
│   │   ├── 0001-imx-add-i.MX8MP-FRDM-board-support.patch                # 基本板支援
│   │   ├── 0002-imx-add-i.MX8MP-FRDM-Board-basic-Android-Support.patch  # Android boot
│   │   └── 0003-net-phy-motorcomm-Add-support-for-YT8521-PHY.patch      # 網路 PHY driver
│   ├── kernel/
│   │   ├── 0001-ANDROID-GKI-Add-symbol-to-symbol-list-for-imx.patch     # GKI symbol (devm_nvmem_device_put)
│   │   ├── 0001-arm64-dts-Add-i.MX8MP-FRDM-board-support.patch          # 基本 DTS
│   │   ├── 0002 ~ 0010                                                   # 攝影機、LVDS、WiFi 等 DTS
│   │   └── (共 11 個 patch)
│   └── mkimage/
│       └── 0001-imx-add-i.MX8MP-FRDM-board-android-support.patch        # mkimage 支援
```

## Apply Patch 步驟

**前提：** Build tree 必須是乾淨狀態（`git status` 無改動）。如果有 SRG 修改，先用 `original/` 還原。

```bash
BUILD=/mnt/data/imx-android-14.0.0_2.2.0/android_build
PATCHES=~/srg-imx8pl-android14-porting/reference/patches/frdm8mp_android14_patch

# 1. device/nxp（用 git apply，不產生 commit）
cd ${BUILD}/device/nxp
git apply --check ${PATCHES}/device_nxp/*.patch && \
git apply ${PATCHES}/device_nxp/*.patch

# 2. uboot-imx（用 git am，產生 commit）
cd ${BUILD}/vendor/nxp-opensource/uboot-imx
git am ${PATCHES}/vendor/uboot/*.patch

# 3. kernel_imx（用 git am --3way，因為 GKI symbol patch context 不完全匹配 2.2.0）
cd ${BUILD}/vendor/nxp-opensource/kernel_imx
git am --3way ${PATCHES}/vendor/kernel/*.patch

# 4. imx-mkimage（用 git am）
cd ${BUILD}/vendor/nxp-opensource/imx-mkimage
git am ${PATCHES}/vendor/mkimage/*.patch
```

### 注意事項

- **kernel patch 必須用 `--3way`**：第一個 patch（GKI symbol list）的 context 是基於 2.1.0，在 2.2.0 上 context 不匹配，但 `--3way` 可以正確 merge
- **device/nxp 用 `git apply`（不是 `git am`）**：因為 patch 格式不含 commit metadata，只能 apply 到 working tree
- GKI symbol patch 在 2.2.0 上會顯示 "No changes -- Patch already applied"（`devm_nvmem_device_put` 在 2.2.0 已存在），屬正常

### 2.1.0 → 2.2.0 相容性修正

FRDM patch 是基於 2.1.0 製作的，apply 到 2.2.0 後需要額外修正：

| 問題 | 原因 | 修法 |
|------|------|------|
| `pwrseq_simple.ko` missing | 2.2.0 GKI defconfig 改為 `# CONFIG_PWRSEQ_SIMPLE is not set`，且 `imx8mp_gki.fragment` 未補上，導致模組不產出。但 FRDM DTS 仍有 `mmc-pwrseq-simple` 節點（IW612 WiFi SDIO 需要） | 在 `imx8mp_gki.fragment` 末尾加上 `CONFIG_PWRSEQ_SIMPLE=m`，保留 `SharedBoardConfig.mk` 中的 .ko |
| `CONFIG_DEBUG_INFO_BTF` build 失敗 | host 的 pahole v1.25 與 Android clang 18 的 DWARF5 不相容 | `gki_defconfig` 改為 `CONFIG_DEBUG_INFO_BTF=n`（或升級 pahole >= 1.26） |

#### pwrseq_simple 背景說明

`pwrseq_simple` 是 Linux MMC 子系統的 power sequence 驅動（`drivers/mmc/core/pwrseq_simple.c`），用於在 SDIO 裝置 probe 前透過 GPIO 完成 reset 時序。FRDM 板的 IW612 WiFi 透過 SDIO 連接，DTS 中定義了完整的上電流程：

```
reg_usdhc1_vmmc (regulator-fixed)     → WLAN_EN 供電（20ms startup delay）
usdhc1_pwrseq (mmc-pwrseq-simple)     → GPIO2_IO10 reset 時序
&usdhc1: vmmc-supply + mmc-pwrseq     → 兩者綁定到 SDIO controller
```

2.1.0 的 `gki_defconfig` 直接包含 `CONFIG_PWRSEQ_SIMPLE=m`，2.2.0 時 Google GKI 升級把它關閉了，NXP 的 `imx8mp_gki.fragment` 未同步補上，造成模組缺失。注意：EVK 基本設定不使用此機制（EVK DTS 無 `mmc-pwrseq-simple` 節點），只有 FRDM 和 EVK+M.2 WiFi overlay 才需要。

新的 generic power sequencing 子系統（`drivers/power/sequencing/`，Linux 6.11+）在此 kernel (5.15) 中不存在，`pwrseq_simple` 並未被取代。

### 修正檔案（手動加入）：

**1.** `vendor/nxp-opensource/kernel_imx/arch/arm64/configs/imx8mp_gki.fragment` — 末尾加入：
```
# Power sequence (wifi)
CONFIG_PWRSEQ_SIMPLE=m
```

**2.** `device/nxp/imx8m/frdm_8mp/SharedBoardConfig.mk` — 保留既有的（不需改動）：
```
$(KERNEL_OUT)/drivers/mmc/core/pwrseq_simple.ko \
```

**3.** `vendor/nxp-opensource/kernel_imx/arch/arm64/configs/gki_defconfig` — 已改為（BTF 修正）：
```
CONFIG_DEBUG_INFO_BTF=n
```

### Apply 結果（2026-03-03 確認）

| Repo | Patch 數量 | 方式 | 產生 Commit |
|------|-----------|------|------------|
| device/nxp | 1 | `git apply` | 否（working tree） |
| uboot-imx | 3 | `git am` | 3 個 commit |
| kernel_imx | 11 | `git am --3way` | 10 個 commit（第 1 個已存在跳過） |
| imx-mkimage | 1 | `git am` | 1 個 commit |

## Build

```bash
cd ${BUILD}
export AARCH64_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
export AARCH32_GCC_CROSS_COMPILE=/opt/gcc-arm-9.2-2019.12-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-
export CLANG_PATH=$(pwd)/prebuilts/clang/host/linux-x86
source build/envsetup.sh
lunch frdm_8mp-trunk_staging-userdebug
./imx-make.sh -j$(nproc) 2>&1 | tee build-log.txt
```

產出在：`out/target/product/frdm_8mp/`

## Flash（UUU 燒 eMMC）

```bash
cd out/target/product/frdm_8mp

# GKI 陷阱：確認 boot.img 是 imx kernel（~14MB），不是 GKI（~35MB）
ls -lh boot.img boot-imx.img
# 如果 boot.img 是 35MB → cp boot-imx.img boot.img

# 設定 FRDM 板 SW5 boot mode = 0001（serial download mode）
# USB cable 連接 PORT1 到 PC
sudo ./uuu_imx_android_flash.sh -f imx8mp -p frdm -a -e
# 或是 sd card
sudo ./imx-sdcard-partition.sh -f imx8mp -a -D . /dev/sdX
```

Flash 完成後，將 SW5 boot mode 改為 `0010`（eMMC boot）再開機。

## 還原（移除 FRDM patch）

```bash
# uboot-imx：移除 3 個 commit
cd ${BUILD}/vendor/nxp-opensource/uboot-imx
git reset --hard HEAD~3

# kernel_imx：移除 10 個 commit
cd ${BUILD}/vendor/nxp-opensource/kernel_imx
git reset --hard HEAD~10

# imx-mkimage：移除 1 個 commit
cd ${BUILD}/vendor/nxp-opensource/imx-mkimage
git reset --hard HEAD~1

# device/nxp：git checkout 還原 working tree
cd ${BUILD}/device/nxp
git checkout .
```

---

## 原始文件（NXP 提供）

以下為 NXP 原始 patch note 英文版，保留供參考。

---

Customer may want to deploy Android 14 on FRDM-iMX8MP. This doc gives an introduction about how to deploy Android OS14 on FRDM-iMX8MP

Hardware:

FRDM-iMX8MP, Power supply cable, usb cable x2,

Ubuntu PC

Outline:

Follow the below steps:

Setup the Android 14 source environment based on LF6.6.36.
Apply FRDM-iMX8MP patches in kernel, uboot, mkimage, and device directory.
Build the image for FRDM-iMX8MP
Flash the image


1. Setup the environment

On the Linux PC, set up the Android Source environment according to Section 2- Section 3 from the Android User's Guide Rev. android-14.0.0_2.1.0 and do not build the image yet.
$ cd ~ (or any other directory you like)
$ tar xzvf imx-android-14.0.0_2.1.0.tar.gz
To generate the i.MX Android release source code build environment, execute the following commands:
$ source ~/imx-android-14.0.0_2.1.0/imx_android_setup.sh
Prepare the build environment for U-Boot and Linux kernel. This step is mandatory because there is no GCC cross-compile tool chain in the one in AOSP codebase. An approach is provided to use the self-installed GCC cross-compile tool chain for both AArch32 and AArch64.
Change to the top-level build directory and set up the environment for building. This only configures the current terminal
$ cd ${MY_ANDROID}
$ source build/envsetup.sh
2. Apply FRDM-iMX8MP patches into AOSP



Apply the patch in device/nxp, copy all the patches into android_build/device/nxp, and then running the command:
$ git apply --check 0001-device-nxp-add-FRDM-i.MX8MP-Android14-basic-support.patch
$ git apply 0001-device-nxp-add-FRDM-i.MX8MP-Android14-basic-support.patch
Apply the patches in uboot, copy all the patches into android_build/vendor/nxp-opensource/uboot-imx, and then running the command:
$ git am *.patch
Apply the patches in kernel, copy all the patches into android_build/vendor/nxp-opensource/kernel-imx, and then running the command:
$ git am *.patch
Apply the patch in mkimage, copy all the patches into android_build/vendor/nxp-opensource/ imx-mkimage, and then running the command:
$ git am *.patch




3. Build the image for FRDM-iMX8MP

Execute the Android lunch command:
$ lunch frdm_8mp-trunk_staging-userdebug
Execute the imx-make.sh script to generate the image.
$ ./imx-make.sh -j4 2>&1 | tee build-log.txt
NOTE: The following outputs are generated by default in ${MY_ANDROID}/out/target/product/frdm_8mp:


4. Flash the image

The board image files can be flashed into the target board using Universal Update Utility (UUU).

For the UUU binary file, download it from GitHub: uuu release page on GitHub.

To achieve more flexibility, two script files are provided to invoke UUU to automatically flash all Android images.

uuu_imx_android_flash.sh for Linux OS
uuu_imx_android_flash.bat for Windows OS
For this release, these two scripts are validated on UUU 1.5.179 version. Download the corresponding version from GitHub:

For Linux OS, download the file named uuu.
For Windows OS, download the file named uuu.exe.
Perform the following steps to download the board images:

Download the UUU binary file from GitHub as described before. Install UUU into a directory contained by the system environment variable of "PATH".
Make the board enter serial download mode. Change the board's SW5 (boot mode) to 0001 (from 1-4 bit) to enter serial download mode.
Power on the board. Use the USB cable to connect the USB 3.0 dual-role port (with silkprint "PORT1") on the board to your host PC.
On the Linux system, open the shell terminal. For example, you can execute a command as follows:
$ sudo ./uuu_imx_android_flash.sh -f imx8mp -p frdm -a -e
On the Windows system, open the command-line interface in administrator mode. The corresponding command is as follows:
$ uuu_imx_android_flash.bat -f imx8mp -p frdm -a -e
NOTE: If you want to change the dtb, you can add -d dtb_feature. Also, you can check all the info by using the command: uuu_imx_android_flash.bat

Power off the board and Change the board's SW5 (boot mode) to 0010 (from 1-4 bit) to enter emmc boot mode
