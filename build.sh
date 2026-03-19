#!/bin/bash

# ======================================================
# 🚀 Linkit2me Kernel Build Script - Boot Fixed Edition
# Matched with Stock AIK Parameters for J320H
# ======================================================

abort() {
    echo "-----------------------------------------------"
    echo "❌ BUILD FAILED! check logs for errors."
    echo "-----------------------------------------------"
    exit 1
}

# --- 1. إعدادات الهوية والبيئة ---
export ARCH=arm
export KBUILD_BUILD_USER="imad"
export KBUILD_BUILD_HOST="Linkit2me-Lab"
OUT_DIR="out"
mkdir -p $OUT_DIR

# --- 2. إعداد المترجم (Toolchain) ---
TOOLCHAIN_BIN=$PWD/toolchain/bin/arm-linux-androideabi-
export CROSS_COMPILE=$TOOLCHAIN_BIN

if [ ! -f "${TOOLCHAIN_BIN}gcc" ]; then
    echo "❌ Toolchain not found at $TOOLCHAIN_BIN"
    abort
fi

if command -v ccache >/dev/null 2>&1; then
    export CCACHE_DIR="$PWD/.ccache"
    export CROSS_COMPILE="ccache $TOOLCHAIN_BIN"
fi

# --- 3. تعديل قيم الـ Boot الحساسة (مطابقة للـ AIK) ---
# تم تغيير الـ BASE والـ SECOND والـ CMDLINE لضمان الإقلاع
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
SECOND_OFFSET=0x00f00000
TAGS_OFFSET=0x00000100
PAGESIZE=2048
# السطر الأصلي للجهاز مع إضافة permissive
CMDLINE="console=ttyS1,115200n8 androidboot.selinux=permissive"

BASE_CONFIG=j3x3g-dt_defconfig
REC_CONFIG=recovery.config
RAMDISK_SRC="build/ramdisk"
RAMDISK_OUT="$OUT_DIR/ramdisk.cpio.gz"
DT_FILE="build/boot.img-dt" 
OUTPUT_BOOTIMG="$OUT_DIR/boot.img"

# --- 4. التحضير والبناء ---
echo "--- 🛠️ Preparing build environment ---"
make O=$OUT_DIR mrproper || abort
make O=$OUT_DIR $BASE_CONFIG || abort

if [ -f arch/arm/configs/$REC_CONFIG ]; then
    echo "--- 🩹 Applying Recovery patches ---"
    cat arch/arm/configs/$REC_CONFIG >> $OUT_DIR/.config
    make O=$OUT_DIR olddefconfig || abort
fi

echo "--- ⚡ Starting Compilation ---"
make O=$OUT_DIR KCFLAGS="-fcommon" HOSTCFLAGS="-fcommon" -j$(nproc --all) zImage dtbs || abort

# --- 5. بناء أداة mkbootimg ---
build_tools() {
    echo "--- 🛠️ Building mkbootimg from source ---"
    rm -rf mkbootimg_src toolchain/mkbootimg
    git clone https://github.com/osm0sis/mkbootimg.git mkbootimg_src || abort
    cd mkbootimg_src
    make CROSS_COMPILE= CC=gcc mkbootimg -j$(nproc --all) || abort
    cp mkbootimg ../toolchain/mkbootimg
    cd ..
    rm -rf mkbootimg_src
    chmod +x toolchain/mkbootimg
}

if [ ! -f "toolchain/mkbootimg" ] || [ "$(grep -c "404" toolchain/mkbootimg)" -gt 0 ]; then
    build_tools
fi

# --- 6. تجميع الـ Image النهائي ببارامترات سامسونج ---
echo "-----------------------------------------------"
if [ -f $OUT_DIR/arch/arm/boot/zImage ]; then
    echo "✅ Kernel built. Packing Boot Image..."

    # ضغط الرام ديسك (تأكد أن مجلد build/ramdisk يحتوي ملفاتك)
    if [ -d "$RAMDISK_SRC" ]; then
        pushd $RAMDISK_SRC > /dev/null
        find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../../$RAMDISK_OUT || abort
        popd > /dev/null
    fi

    # إنشاء البوت إيمج باستخدام القيم الجديدة
    ./toolchain/mkbootimg \
        --kernel $OUT_DIR/arch/arm/boot/zImage \
        --ramdisk $RAMDISK_OUT \
        --cmdline "$CMDLINE" \
        --base $BASE \
        --pagesize $PAGESIZE \
        --kernel_offset $KERNEL_OFFSET \
        --ramdisk_offset $RAMDISK_OFFSET \
        --second_offset $SECOND_OFFSET \
        --tags_offset $TAGS_OFFSET \
        -o $OUTPUT_BOOTIMG || abort

    # دمج الـ DT وتوقيع سامسونج (SEANDROIDENFORCE)
    if [ -f "$DT_FILE" ]; then
        echo "--- ➕ Appending Stock DTB & Signature ---"
        cat $DT_FILE >> $OUTPUT_BOOTIMG
        echo -n "SEANDROIDENFORCE" >> $OUTPUT_BOOTIMG
    fi

    echo "-----------------------------------------------"
    echo "🎉 SUCCESS! boot.img is ready for J320H."
    echo "-----------------------------------------------"
else
    abort
fi
