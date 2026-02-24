#!/bin/bash
# Restore Original NXP EVK Files

ANDROID_BUILD="/mnt/data/imx-android-14.0.0_2.2.0/android_build"
REPO_DIR="/home/hao/srg-imx8pl-android14-porting"

echo "Restoring Original NXP EVK Files from ${REPO_DIR}..."

# 1. Kernel DTS
if [ -f "${REPO_DIR}/kernel/dts/imx8mp-evk.dts.orig" ]; then
    cp -v "${REPO_DIR}/kernel/dts/imx8mp-evk.dts.orig" "${ANDROID_BUILD}/vendor/nxp-opensource/kernel_imx/arch/arm64/boot/dts/freescale/imx8mp-evk.dts"
else
    echo "Warning: Original Kernel DTS not found."
fi

# 2. U-Boot Board Files
if [ -f "${REPO_DIR}/uboot/board/lpddr4_timing.c.orig" ]; then
    cp -v "${REPO_DIR}/uboot/board/lpddr4_timing.c.orig" "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/board/freescale/imx8mp_evk/lpddr4_timing.c"
else
    echo "Warning: Original lpddr4_timing.c not found."
fi

if [ -f "${REPO_DIR}/uboot/board/imx8mp_evk.h.orig" ]; then
    cp -v "${REPO_DIR}/uboot/board/imx8mp_evk.h.orig" "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/include/configs/imx8mp_evk.h"
else
    echo "Warning: Original imx8mp_evk.h not found."
fi

# 3. SPL DTS (Attempt to restore if file exists, otherwise warn)
if [ -f "${REPO_DIR}/uboot/spl_dts/imx8mp-evk-u-boot.dtsi.orig" ]; then
    cp -v "${REPO_DIR}/uboot/spl_dts/imx8mp-evk-u-boot.dtsi.orig" "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/arch/arm/dts/imx8mp-evk-u-boot.dtsi"
else
    echo "Warning: Original SPL DTS not found in ${REPO_DIR}/uboot/spl_dts/. Skipping."
fi

# 4. Build Scripts
if [ -f "${REPO_DIR}/scripts/build/AndroidUboot.sh.orig" ]; then
    cp -v "${REPO_DIR}/scripts/build/AndroidUboot.sh.orig" "${ANDROID_BUILD}/device/nxp/imx8m/evk_8mp/AndroidUboot.sh"
else
    echo "Warning: Original AndroidUboot.sh reconstruction failed/missing."
fi

if [ -f "${REPO_DIR}/scripts/build/pad_image.sh" ]; then
     # Note: We don't have a .orig for pad_image.sh in the new plan, assuming the script in scripts/build is the modified one?
     # Wait, let's look at the copy command: cp src_backup/build_scripts/pad_image.sh scripts/build/pad_image.sh
     # We didn't copy a .orig for pad_image.sh in the previous step because it wasn't in src_original?
     # Let's check the previous ls -R output.
     # src_backup had pad_image.sh. src_original did NOT have pad_image.sh.
     # So I should probably remove this restore block or comment it out if there is no original to restore.
     # Or maybe the user implies checking if a backup exists somewhere else?
     # For now, I will omit the restore of pad_image.sh if I don't have the original source.
     echo "Skipping pad_image.sh restore (No original backup found in repo)."
else
    echo "Warning: pad_image.sh check skipped."
fi

echo "Restore operation complete."
