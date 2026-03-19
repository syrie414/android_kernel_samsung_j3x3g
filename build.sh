#!/bin/bash

# دالة إيقاف السكربت عند حدوث خطأ
abort() {
    echo "-----------------------------------------------"
    echo "❌ Kernel compilation or packing failed! Exiting..."
    echo "-----------------------------------------------"
    exit 1
}

# --- 1. إعدادات الهوية والبيئة ---
export ARCH=arm
export KBUILD_BUILD_USER="imad"
export KBUILD_BUILD_HOST="Linkit2me-Lab"

# مسار المترجم (تأكد من وجوده)
TOOLCHAIN_PATH=$PWD/toolchain/bin/arm-linux-androideabi-
export CROSS_COMPILE=$TOOLCHAIN_PATH

# الملفات النشطة حالياً
BASE_CONFIG=j3x3g-dt_defconfig
REC_CONFIG=recovery.config

# إعدادات معالج Spreadtrum SC8830 (J320H) لبناء الـ boot.img
BASE=0x00000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x00000100
SECOND_OFFSET=0x00f00000
PAGESIZE=2048
CMDLINE="console=ttyS1,115200n8 loglevel=8 init=/init root=/dev/ram0 rw"

# مسارات الملفات
OUT_DIR="out"
RAMDISK_SRC="build/ramdisk"
RAMDISK_OUT="$OUT_DIR/ramdisk.cpio.gz"
DT_FILE="build/boot.img-dt" # تأكد أن هذا الملف موجود في المستودع
OUTPUT_BOOTIMG="$OUT_DIR/boot.img"

# --- 2. تنظيف البيئة ---
echo "--- Cleaning build directory ---"
rm -rf $OUT_DIR
mkdir -p $OUT_DIR
make O=$OUT_DIR mrproper || abort

# --- 3. دمج الإعدادات (Base + Recovery) ---
echo "--- Merging configs: $BASE_CONFIG + $REC_CONFIG ---"
if [ ! -f arch/arm/configs/$BASE_CONFIG ]; then
    echo "ERROR: Base config not found in arch/arm/configs/!" && abort
fi

# بناء الكونسفج الأساسي
make O=$OUT_DIR $BASE_CONFIG || abort

# دمج إعدادات الريكفري
if [ -f arch/arm/configs/$REC_CONFIG ]; then
    echo "Applying Recovery Config patches..."
    cat arch/arm/configs/$REC_CONFIG >> $OUT_DIR/.config
    make O=$OUT_DIR olddefconfig || abort
else
    echo "WARNING: Recovery config not found, skipping merge."
fi

# --- 4. بدء البناء الفعلي (Kernel + DTBs) ---
echo "--- Starting Compilation for J320H ---"
make O=$OUT_DIR KCFLAGS="-fcommon" HOSTCFLAGS="-fcommon" -j$(nproc --all) zImage dtbs || abort

# --- 5. تجهيز Ramdisk وبناء boot.img ---
echo "-----------------------------------------------"
if [ -f $OUT_DIR/arch/arm/boot/zImage ]; then
    echo "✅ Kernel (zImage) built successfully."
    
    # التحقق من وجود مجلد الرامديسك
    if [ ! -d "$RAMDISK_SRC" ]; then
        echo "ERROR: Ramdisk folder not found at $RAMDISK_SRC!" && abort
    fi

    # 5.1 بناء الـ Ramdisk
    echo "--- Packing RAMDisk ---"
    pushd $RAMDISK_SRC > /dev/null
    find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../../$RAMDISK_OUT || abort
    popd > /dev/null
    echo "✅ RAMDisk packed successfully."

    # 5.2 التحقق من وجود mkbootimg وتنزيله إذا لزم الأمر
    if [ ! -f "toolchain/mkbootimg" ]; then
        echo "Downloading mkbootimg..."
        curl -sL https://raw.githubusercontent.com/osm0sis/mkbootimg/master/mkbootimg -o toolchain/mkbootimg
        chmod +x toolchain/mkbootimg
    fi

    # 5.3 بناء boot.img
    echo "--- Creating boot.img ---"
    ./toolchain/mkbootimg \
        --kernel $OUT_DIR/arch/arm/boot/zImage \
        --ramdisk $RAMDISK_OUT \
        --dt $DT_FILE \
        --cmdline "$CMDLINE" \
        --base $BASE \
        --pagesize $PAGESIZE \
        --kernel_offset $KERNEL_OFFSET \
        --ramdisk_offset $RAMDISK_OFFSET \
        --second_offset $SECOND_OFFSET \
        --tags_offset $TAGS_OFFSET \
        -o $OUTPUT_BOOTIMG || abort

    echo "-----------------------------------------------"
    echo "🎉 SUCCESS! boot.img is ready."
    echo "Location: $OUTPUT_BOOTIMG"
    du -h $OUTPUT_BOOTIMG
    echo "-----------------------------------------------"
else
    echo "❌ BUILD FAILED! zImage not found."
    abort
fi
