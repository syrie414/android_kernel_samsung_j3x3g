#!/bin/bash
set -euo pipefail

# ======================================================
# Linkit2me Kernel Build Script - No Stock DT Edition
# J320H
# ======================================================

abort() {
    echo "-----------------------------------------------"
    echo "❌ BUILD FAILED! check logs for errors."
    echo "-----------------------------------------------"
    exit 1
}

trap 'abort' ERR

# --- 1. إعدادات الهوية والبيئة ---
export ARCH=arm
export SUBARCH=arm
export KBUILD_BUILD_USER="imad"
export KBUILD_BUILD_HOST="Linkit2me-Lab"

OUT_DIR="out"
mkdir -p "$OUT_DIR"

# --- 2. إعداد المترجم (Toolchain) ---
TOOLCHAIN_BIN="$PWD/toolchain/bin/arm-linux-androideabi-"

if [ ! -f "${TOOLCHAIN_BIN}gcc" ]; then
    echo "❌ Toolchain not found at ${TOOLCHAIN_BIN}"
    abort
fi

export CROSS_COMPILE="$TOOLCHAIN_BIN"

if command -v ccache >/dev/null 2>&1; then
    export CCACHE_DIR="$PWD/.ccache"
    export CROSS_COMPILE="ccache $TOOLCHAIN_BIN"
fi

# --- 3. Boot parameters ---
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0x00f00000
TAGS_OFFSET=0x00000100
PAGESIZE=2048
CMDLINE="console=ttyS1,115200n8 androidboot.selinux=permissive"

BASE_CONFIG="j3x3g-dt_defconfig"
REC_CONFIG="recovery.config"

RAMDISK_SRC="build/ramdisk"
RAMDISK_OUT="$OUT_DIR/ramdisk.cpio.gz"

DTB_DIR="$OUT_DIR/arch/arm/boot/dts"
DTB_IMG="$OUT_DIR/dtb.img"

OUTPUT_BOOTIMG="$OUT_DIR/boot.img"
MKBOOTIMG="./toolchain/mkbootimg"

JOBS="$(nproc --all 2>/dev/null || nproc)"

# --- 4. التحضير والبناء ---
echo "--- 🛠️ Preparing build environment ---"
make O="$OUT_DIR" mrproper
make O="$OUT_DIR" "$BASE_CONFIG"

if [ -f "arch/arm/configs/$REC_CONFIG" ]; then
    echo "--- 🩹 Applying Recovery patches ---"
    cat "arch/arm/configs/$REC_CONFIG" >> "$OUT_DIR/.config"
    make O="$OUT_DIR" olddefconfig
fi

echo "--- ⚡ Starting Compilation ---"
make O="$OUT_DIR" KCFLAGS="-fcommon" HOSTCFLAGS="-fcommon" -j"$JOBS" zImage dtbs

# --- 5. تجهيز DTB من ناتج الكيرنل نفسه ---
echo "--- 📦 Packing DTB from kernel build output ---"
if [ ! -d "$DTB_DIR" ]; then
    echo "❌ DTB directory not found: $DTB_DIR"
    abort
fi

mapfile -d '' DTB_FILES < <(find "$DTB_DIR" -maxdepth 1 -name "*.dtb" -print0 | sort -z)
if [ "${#DTB_FILES[@]}" -eq 0 ]; then
    echo "❌ No dtb files found in $DTB_DIR"
    abort
fi

cat "${DTB_FILES[@]}" > "$DTB_IMG"

# --- 6. تجهيز الرامديسك ---
if [ -d "$RAMDISK_SRC" ]; then
    echo "--- 📦 Packing ramdisk ---"
    (
        cd "$RAMDISK_SRC"
        find . | LC_ALL=C sort | cpio -o -H newc -R root:root
    ) | gzip -9n > "$RAMDISK_OUT"
else
    echo "❌ Ramdisk folder not found: $RAMDISK_SRC"
    abort
fi

# --- 7. التحقق من mkbootimg ---
if [ ! -x "$MKBOOTIMG" ]; then
    echo "❌ mkbootimg not found or not executable at $MKBOOTIMG"
    abort
fi

# --- 8. اختيار kernel image ---
KERNEL_IMAGE="$OUT_DIR/arch/arm/boot/zImage"
USE_DTB_ARG=1

if [ -f "$OUT_DIR/arch/arm/boot/zImage-dtb" ]; then
    echo "--- ✅ Found zImage-dtb, using appended DTB kernel image ---"
    KERNEL_IMAGE="$OUT_DIR/arch/arm/boot/zImage-dtb"
    USE_DTB_ARG=0
fi

# --- 9. إنشاء boot.img ---
echo "-----------------------------------------------"
echo "✅ Kernel built. Packing Boot Image..."

if [ "$USE_DTB_ARG" -eq 1 ]; then
    "$MKBOOTIMG" \
        --kernel "$KERNEL_IMAGE" \
        --ramdisk "$RAMDISK_OUT" \
        --dt "$DTB_IMG" \
        --cmdline "$CMDLINE" \
        --base "$BASE" \
        --pagesize "$PAGESIZE" \
        --kernel_offset "$KERNEL_OFFSET" \
        --ramdisk_offset "$RAMDISK_OFFSET" \
        --second_offset "$SECOND_OFFSET" \
        --tags_offset "$TAGS_OFFSET" \
        -o "$OUTPUT_BOOTIMG"
else
    "$MKBOOTIMG" \
        --kernel "$KERNEL_IMAGE" \
        --ramdisk "$RAMDISK_OUT" \
        --cmdline "$CMDLINE" \
        --base "$BASE" \
        --pagesize "$PAGESIZE" \
        --kernel_offset "$KERNEL_OFFSET" \
        --ramdisk_offset "$RAMDISK_OFFSET" \
        --second_offset "$SECOND_OFFSET" \
        --tags_offset "$TAGS_OFFSET" \
        -o "$OUTPUT_BOOTIMG"
fi

# --- 10. توقيع سامسونج ---
echo "--- ➕ Appending SEANDROIDENFORCE signature ---"
echo -n "SEANDROIDENFORCE" >> "$OUTPUT_BOOTIMG"

echo "-----------------------------------------------"
echo "🎉 SUCCESS! boot.img is ready for J320H."
echo "-----------------------------------------------"
