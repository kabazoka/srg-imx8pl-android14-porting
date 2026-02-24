#!/bin/bash
#
# apply-platform.sh - Switch between EVK and SRG platform configurations
#
# Usage: ./apply-platform.sh [evk|srg]
#
# This script copies the appropriate U-Boot configuration files to the
# Android build tree for the selected platform.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTING_DIR="$(dirname "$SCRIPT_DIR")"

# Default Android build directory - adjust if needed
ANDROID_BUILD="${ANDROID_BUILD:-/mnt/data/imx-android-14.0.0_2.2.0/android_build}"

UBOOT_HEADER_DEST="${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/include/configs/imx8mp_evk.h"
UBOOT_TIMING_DEST="${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/board/freescale/imx8mp_evk/lpddr4_timing.c"
UBOOT_DTS_DEST="${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/arch/arm/dts/imx8mp-evk.dts"
UBOOT_DTSI_DEST="${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/arch/arm/dts/imx8mp-evk-u-boot.dtsi"
UBOOT_DEFCONFIG_DEST="${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx/configs/imx8mp_evk_android_defconfig"

usage() {
    echo "Usage: $0 [evk|srg]"
    echo ""
    echo "Platforms:"
    echo "  evk  - NXP i.MX8MP EVK (6GB DDR, UART2 console)"
    echo "  srg  - SRG-iMX8PL (4GB DDR, UART4 console)"
    echo ""
    echo "Environment variables:"
    echo "  ANDROID_BUILD - Path to Android build tree (default: /mnt/data/imx-android-14.0.0_2.2.0/android_build)"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

PLATFORM="$1"

case "$PLATFORM" in
    evk)
        echo "==> Applying EVK configuration (6GB DDR, UART2)"
        # Use .orig files for EVK
        SOURCE_SUFFIX=".orig"
        ;;
    srg)
        echo "==> Applying SRG configuration (4GB DDR, UART4)"
        # Use standard files for SRG
        SOURCE_SUFFIX=""
        ;;
    *)
        echo "Error: Unknown platform '$PLATFORM'"
        usage
        ;;
esac

SOURCE_BOARD_DIR="${PORTING_DIR}/uboot/board"
SOURCE_DTS_DIR="${PORTING_DIR}/uboot/dts"
SOURCE_SPL_DTS_DIR="${PORTING_DIR}/uboot/spl_dts"

# Check source files exist
if [ ! -f "${SOURCE_BOARD_DIR}/imx8mp_evk.h${SOURCE_SUFFIX}" ]; then
    echo "Error: ${SOURCE_BOARD_DIR}/imx8mp_evk.h${SOURCE_SUFFIX} not found"
    exit 1
fi

if [ ! -f "${SOURCE_BOARD_DIR}/lpddr4_timing.c${SOURCE_SUFFIX}" ]; then
    echo "Error: ${SOURCE_BOARD_DIR}/lpddr4_timing.c${SOURCE_SUFFIX} not found"
    exit 1
fi

# Check destination directory exists
if [ ! -d "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx" ]; then
    echo "Error: Android build tree not found at ${ANDROID_BUILD}"
    echo "Set ANDROID_BUILD environment variable to the correct path"
    exit 1
fi

# Copy board files
echo "Copying imx8mp_evk.h${SOURCE_SUFFIX}..."
cp "${SOURCE_BOARD_DIR}/imx8mp_evk.h${SOURCE_SUFFIX}" "${UBOOT_HEADER_DEST}"

echo "Copying lpddr4_timing.c${SOURCE_SUFFIX}..."
cp "${SOURCE_BOARD_DIR}/lpddr4_timing.c${SOURCE_SUFFIX}" "${UBOOT_TIMING_DEST}"

# Copy DTS files (SRG has modified versions, EVK uses originals)
if [ -f "${SOURCE_DTS_DIR}/imx8mp-evk.dts${SOURCE_SUFFIX}" ]; then
    echo "Copying imx8mp-evk.dts${SOURCE_SUFFIX}..."
    cp "${SOURCE_DTS_DIR}/imx8mp-evk.dts${SOURCE_SUFFIX}" "${UBOOT_DTS_DEST}"
fi

if [ -f "${SOURCE_SPL_DTS_DIR}/imx8mp-evk-u-boot.dtsi${SOURCE_SUFFIX}" ]; then
    echo "Copying imx8mp-evk-u-boot.dtsi${SOURCE_SUFFIX}..."
    cp "${SOURCE_SPL_DTS_DIR}/imx8mp-evk-u-boot.dtsi${SOURCE_SUFFIX}" "${UBOOT_DTSI_DEST}"
fi

# Copy defconfig if available
if [ -f "${SOURCE_BOARD_DIR}/imx8mp_evk_android_defconfig${SOURCE_SUFFIX}" ]; then
    echo "Copying imx8mp_evk_android_defconfig${SOURCE_SUFFIX}..."
    cp "${SOURCE_BOARD_DIR}/imx8mp_evk_android_defconfig${SOURCE_SUFFIX}" "${UBOOT_DEFCONFIG_DEST}"
else
    echo "(No platform-specific defconfig, using existing)"
fi

echo ""
echo "==> Platform '${PLATFORM}' applied successfully!"
echo ""
echo "Next steps:"
echo "  1. cd ${ANDROID_BUILD}"
echo "  2. source build/envsetup.sh"
echo "  3. lunch evk_8mp-trunk_staging-userdebug"
echo "  4. ./imx-make.sh bootloader -j\$(nproc)"
echo ""
