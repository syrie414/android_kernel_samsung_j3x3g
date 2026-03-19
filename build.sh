#!/bin/bash

# ======================================================
# 🚀 Linkit2me Kernel Build Script for Samsung J320H
# Optimized for ExtremeKernel TWRP & System
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

TOOLCHAIN_PATH=$PWD/toolchain/bin/arm-linux-androideabi-
export CROSS_COMPILE=$TOOLCHAIN_PATH

BASE_CONFIG=j3x3g-dt_defconfig
REC_CONFIG=recovery.config

# --- 2. إعدادات البوت ---
BASE=0x80000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x00000100
PAGESIZE=2048
CMDLINE="init=/sbin/init root=/dev/ram rw console=ttyS1,115200n8 mem=88M androidboot.selinux=permissive"

OUT_DIR="out"
RAMDISK_SRC="build/ramdisk"
RAMDISK_OUT="$OUT_DIR/ramdisk.cpio.gz"
DT_FILE="build/boot.img-dt" 
OUTPUT_BOOTIMG="$OUT_DIR/boot.img"

# --- 3. تجهيز بيئة البناء ---
echo "--- 🛠️ Preparing build environment ---"
rm -rf $OUT_DIR
mkdir -p $OUT_DIR
make O=$OUT_DIR mrproper || abort

# --- 4. دمج الإعدادات ---
echo "--- 📝 Merging configs ---"
if [ ! -f arch/arm/configs/$BASE_CONFIG ]; then
    echo "❌ ERROR: Base config not found!" && abort
fi
make O=$OUT_DIR $BASE_CONFIG || abort

# تطبيق إعدادات ExtremeKernel للريكفري
if [ -f arch/arm/configs/$REC_CONFIG ]; then
    echo "--- 🩹 Applying ExtremeKernel Recovery patches ---"
    cat arch/arm/configs/$REC_CONFIG >> $OUT_DIR/.config
    make O=$OUT_DIR olddefconfig || abort
fi

# --- 5. بناء الكيرنل ---
echo "--- ⚡ Starting Compilation ---"
make O=$OUT_DIR KCFLAGS="-fcommon" HOSTCFLAGS="-fcommon" -j$(nproc --all) zImage dtbs || abort

# --- 6. تجميع الـ Boot Image ---
echo "-----------------------------------------------"
if [ -f $OUT_DIR/arch/arm/boot/zImage ]; then
    echo "✅ Kernel (zImage) built successfully."

    # 6.1 ضغط الـ Ramdisk
    if [ -d "$RAMDISK_SRC" ]; then
        echo "--- 📦 Packing RAMDisk ---"
        pushd $RAMDISK_SRC > /dev/null
        find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../../$RAMDISK_OUT || abort
        popd > /dev/null
    fi

    # 6.2 بناء أداة mkbootimg (الحل النهائي لمشكلة الـ Toolchain)
    echo "--- 🛠️ Force building mkbootimg from source ---"
    rm -f toolchain/mkbootimg
    rm -rf mkbootimg_src
    
    git clone https://github.com/osm0sis/mkbootimg.git mkbootimg_src || abort
    cd mkbootimg_src
    # إجبار استخدام المترجم المحلي (gcc) بدلاً من مترجم الأندرويد لبناء الأداة
    make CC=gcc mkbootimg -j$(nproc --all) || abort
    cp mkbootimg ../toolchain/mkbootimg
    cd ..
    rm -rf mkbootimg_src
    chmod +x toolchain/mkbootimg
    echo "✅ mkbootimg tool built successfully using local GCC."

    # 6.3 صناعة الـ boot.img النهائي
    echo "--- 🖼️ Creating final boot.img ---"
    ./toolchain/mkbootimg \
        --kernel $OUT_DIR/arch/arm/boot/zImage \
        --ramdisk $RAMDISK_OUT \
        --cmdline "$CMDLINE" \
        --base $BASE \
        --pagesize $PAGESIZE \
        --kernel_offset $KERNEL_OFFSET \
        --ramdisk_offset $RAMDISK_OFFSET \
        --tags_offset $TAGS_OFFSET \
        -o $OUTPUT_BOOTIMG || abort

    if [ -f "$DT_FILE" ]; then
        echo "--- ➕ Appending Device Tree (DTB) ---"
        cat $DT_FILE >> $OUTPUT_BOOTIMG
        echo -n "SEANDROIDENFORCE" >> $OUTPUT_BOOTIMG
    fi

    echo "-----------------------------------------------"
    echo "🎉 SUCCESS! ExtremeKernel is ready."
    echo "📊 Size: $(du -h $OUTPUT_BOOTIMG | cut -f1)"
    echo "-----------------------------------------------"
else
    echo "❌ ERROR: Build failed."
    abort
fi
