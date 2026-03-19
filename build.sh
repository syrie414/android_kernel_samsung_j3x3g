#!/bin/bash

# ======================================================
# 🚀 Linkit2me Kernel Build Script for Samsung J320H
# ======================================================

# دالة إيقاف السكربت عند حدوث خطأ مفاجئ
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

# مسار المترجم (Toolchain)
TOOLCHAIN_PATH=$PWD/toolchain/bin/arm-linux-androideabi-
export CROSS_COMPILE=$TOOLCHAIN_PATH

# الملفات النشطة حالياً
BASE_CONFIG=j3x3g-dt_defconfig
REC_CONFIG=recovery.config

# --- 2. إعدادات البوت (مستخرجة من الـ Config الأصلي) ---
# العناوين الفيزيائية لمعالج Spreadtrum SC8830
BASE=0x80000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x00000100
PAGESIZE=2048

# الـ CMDLINE الدقيق للجهاز (تم تعديل الكونسول ليتوافق مع النسخ الحديثة)
CMDLINE="init=/sbin/init root=/dev/ram rw console=ttyS1,115200n8 mem=88M"

# مسارات الملفات والمجلدات
OUT_DIR="out"
RAMDISK_SRC="build/ramdisk"
RAMDISK_OUT="$OUT_DIR/ramdisk.cpio.gz"
DT_FILE="build/boot.img-dt" 
OUTPUT_BOOTIMG="$OUT_DIR/boot.img"

# --- 3. تجهيز بيئة البناء ---
echo "--- 🛠️ Cleaning and preparing build environment ---"
rm -rf $OUT_DIR
mkdir -p $OUT_DIR
# التأكد من تنظيف السورس تماماً
make O=$OUT_DIR mrproper || abort

# --- 4. دمج الإعدادات (Kernel Configs) ---
if [ ! -f arch/arm/configs/$BASE_CONFIG ]; then
    echo "❌ ERROR: Base config ($BASE_CONFIG) not found!" && abort
fi

echo "--- 📝 Merging configs: $BASE_CONFIG ---"
make O=$OUT_DIR $BASE_CONFIG || abort

# دمج إعدادات الريكفري (إذا وجدت)
if [ -f arch/arm/configs/$REC_CONFIG ]; then
    echo "--- 🩹 Applying Recovery patches from $REC_CONFIG ---"
    cat arch/arm/configs/$REC_CONFIG >> $OUT_DIR/.config
    make O=$OUT_DIR olddefconfig || abort
fi

# --- 5. بدء عملية التجميع (Kernel + DTBs) ---
echo "--- ⚡ Starting Compilation (this may take a few minutes) ---"
# KCFLAGS="-fcommon" ضرورية لتجنب أخطاء تعريف المتغيرات في المترجمات الحديثة
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
        echo "✅ RAMDisk is ready."
    else
        echo "⚠️ WARNING: No ramdisk found in $RAMDISK_SRC, image might not boot!"
    fi

    # 6.2 التأكد من أداة mkbootimg
    if [ ! -f "toolchain/mkbootimg" ]; then
        echo "--- 📥 Downloading mkbootimg ---"
        curl -sL https://raw.githubusercontent.com/osm0sis/mkbootimg/master/mkbootimg -o toolchain/mkbootimg
        chmod +x toolchain/mkbootimg
    fi

    # 6.3 صناعة الـ boot.img النهائي
    echo "--- 🖼️ Creating final boot.img ---"
    # ملاحظة: استخدمنا --dt لدمج ملف الـ DT الذي سحبته
    ./toolchain/mkbootimg \
        --kernel $OUT_DIR/arch/arm/boot/zImage \
        --ramdisk $RAMDISK_OUT \
        --dt $DT_FILE \
        --cmdline "$CMDLINE" \
        --base $BASE \
        --pagesize $PAGESIZE \
        --kernel_offset $KERNEL_OFFSET \
        --ramdisk_offset $RAMDISK_OFFSET \
        --tags_offset $TAGS_OFFSET \
        -o $OUTPUT_BOOTIMG || abort

    # 6.4 فحص الحجم النهائي
    echo "-----------------------------------------------"
    echo "🎉 SUCCESS! Your Kernel is ready."
    echo "📍 Path: $OUTPUT_BOOTIMG"
    echo "📊 Size: $(du -h $OUTPUT_BOOTIMG | cut -f1)"
    echo "-----------------------------------------------"
else
    echo "❌ ERROR: zImage was not generated. Build failed."
    abort
fi
