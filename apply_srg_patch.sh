#!/bin/bash
# Apply SRG-iMX8PL Patches (Restore from Backup)

ANDROID_BUILD="/mnt/data/imx-android-14.0.0_2.2.0/android_build"
BACKUP_DIR="/home/hao/srg-imx8pl-android14-porting/src_backup"

echo "Applying SRG Patches from ${BACKUP_DIR}..."

# 1. Kernel DTS
cp -v "${BACKUP_DIR}/kernel_dts/imx8mp-evk.dts" "${ANDROID_BUILD}/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts"

# 2. U-Boot Board Files
cp -v "${BACKUP_DIR}/uboot_board/lpddr4_timing.c" "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/board/freescale/imx8mp_evk/lpddr4_timing.c"
cp -v "${BACKUP_DIR}/uboot_board/imx8mp_evk.h" "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/include/configs/imx8mp_evk.h"

# 3. SPL DTS
cp -v "${BACKUP_DIR}/uboot_spl_dts/imx8mp-evk-u-boot.dtsi" "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/arch/arm/dts/imx8mp-evk-u-boot.dtsi"

# 4. Build Scripts
cp -v "${BACKUP_DIR}/build_scripts/AndroidUboot.sh" "${ANDROID_BUILD}/device/nxp/imx8m/evk_8mp/AndroidUboot.sh"
cp -v "${BACKUP_DIR}/build_scripts/pad_image.sh" "${ANDROID_BUILD}/vendor/nxp-opensource/imx-mkimage/scripts/pad_image.sh"

echo "Done. SRG patches applied."
