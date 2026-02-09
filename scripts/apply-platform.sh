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
        PLATFORM_DIR="${PORTING_DIR}/uboot/evk"
        ;;
    srg)
        echo "==> Applying SRG configuration (4GB DDR, UART4)"
        PLATFORM_DIR="${PORTING_DIR}/uboot/srg"
        ;;
    *)
        echo "Error: Unknown platform '$PLATFORM'"
        usage
        ;;
esac

# Check source files exist
if [ ! -f "${PLATFORM_DIR}/imx8mp_evk.h" ]; then
    echo "Error: ${PLATFORM_DIR}/imx8mp_evk.h not found"
    exit 1
fi

if [ ! -f "${PLATFORM_DIR}/lpddr4_timing.c" ]; then
    echo "Error: ${PLATFORM_DIR}/lpddr4_timing.c not found"
    exit 1
fi

# Check destination directory exists
if [ ! -d "${ANDROID_BUILD}/vendor/nxp-opensource/uboot-imx" ]; then
    echo "Error: Android build tree not found at ${ANDROID_BUILD}"
    echo "Set ANDROID_BUILD environment variable to the correct path"
    exit 1
fi

# Copy files
echo "Copying imx8mp_evk.h..."
cp "${PLATFORM_DIR}/imx8mp_evk.h" "${UBOOT_HEADER_DEST}"

echo "Copying lpddr4_timing.c..."
cp "${PLATFORM_DIR}/lpddr4_timing.c" "${UBOOT_TIMING_DEST}"

echo ""
echo "==> Platform '${PLATFORM}' applied successfully!"
echo ""
echo "Next steps:"
echo "  1. cd ${ANDROID_BUILD}"
echo "  2. source build/envsetup.sh"
echo "  3. lunch evk_8mp-trunk_staging-userdebug"
echo "  4. ./imx-make.sh bootloader -j\$(nproc)"
echo ""
