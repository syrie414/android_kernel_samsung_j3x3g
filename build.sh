#!/bin/bash

# ======================================================
# 🚀 Linkit2me Kernel Build Script - Pro Edition
# Optimized for Samsung J320H (Spreadtrum)
# ======================================================

# 1. دالة الإجهاض عند الخطأ (مثل السكربت الاحترافي)
abort() {
    echo "-----------------------------------------------"
    echo "❌ BUILD FAILED! check logs for errors."
    echo "-----------------------------------------------"
    exit 1
}

# 2. إعدادات الهوية والبيئة
export ARCH=arm
export KBUILD_BUILD_USER="imad"
export KBUILD_BUILD_HOST="Linkit2me-Lab"
OUT_DIR="out"
mkdir -p $OUT_DIR

# 3. إعداد المترجم (Toolchain) - التحقق قبل البدء
TOOLCHAIN_BIN=$PWD/toolchain/bin/arm-linux-androideabi-
export CROSS_COMPILE=$TOOLCHAIN_BIN

if [ ! -f "${TOOLCHAIN_BIN}gcc" ]; then
    echo "❌ Toolchain not found at $TOOLCHAIN_BIN"
    echo "Please ensure the toolchain is cloned into /toolchain directory."
    abort
fi

# 4. تفعيل CCache لتسريع البناء (مثل السكربت الاحترافي)
if command -v ccache >/dev/null 2>&1; then
    echo "✅ ccache detected, speed boost enabled!"
    export CCACHE_DIR="$PWD/.ccache"
    export CROSS_COMPILE="ccache $TOOLCHAIN_BIN"
fi

# 5. إعدادات الـ Boot Image (لجهاز J320H)
BASE=0x80000000
KERNEL_OFFSET=0x00008000
RAMDISK_OFFSET=0x01000000
TAGS_OFFSET=0x00000100
PAGESIZE=2048
CMDLINE="init=/sbin/init root=/dev/ram rw console=ttyS1,115200n8 mem=88M androidboot.selinux=permissive"

BASE_CONFIG=j3x3g-dt_defconfig
REC_CONFIG=recovery.config
RAMDISK_SRC="build/ramdisk"
RAMDISK_OUT="$OUT_DIR/ramdisk.cpio.gz"
DT_FILE="build/boot.img-dt" 
OUTPUT_BOOTIMG="$OUT_DIR/boot.img"

# 6. تنظيف وتجهيز الإعدادات
echo "--- 🛠️ Preparing build environment ---"
make O=$OUT_DIR mrproper || abort
make O=$OUT_DIR $BASE_CONFIG || abort

if [ -f arch/arm/configs/$REC_CONFIG ]; then
    echo "--- 🩹 Applying ExtremeKernel Recovery patches ---"
    cat arch/arm/configs/$REC_CONFIG >> $OUT_DIR/.config
    make O=$OUT_DIR olddefconfig || abort
fi

# 7. البناء الفعلي (Compilation)
echo "--- ⚡ Starting Compilation (j$(nproc --all)) ---"
# إضافة -fcommon لحل مشاكل المترجمات القديمة
make O=$OUT_DIR KCFLAGS="-fcommon" HOSTCFLAGS="-fcommon" -j$(nproc --all) zImage dtbs || abort

# 8. التعامل مع أدوات البناء (mkbootimg) بشكل منعزل (لحل خطأ الـ 404 والـ stdio)
build_tools() {
    echo "--- 🛠️ Compiling mkbootimg from source (Host Mode) ---"
    rm -rf mkbootimg_src toolchain/mkbootimg
    git clone https://github.com/osm0sis/mkbootimg.git mkbootimg_src || abort
    cd mkbootimg_src
    # هنا "السر": نصفر الـ CROSS_COMPILE مؤقتاً لنبني للكمبيوتر وليس للهاتف
    make CROSS_COMPILE= CC=gcc mkbootimg -j$(nproc --all) || abort
    cp mkbootimg ../toolchain/mkbootimg
    cd ..
    rm -rf mkbootimg_src
    chmod +x toolchain/mkbootimg
}

if [ ! -f "toolchain/mkbootimg" ] || [ "$(grep -c "404" toolchain/mkbootimg)" -gt 0 ]; then
    build_tools
fi

# 9. تجميع الـ Image النهائي
echo "-----------------------------------------------"
if [ -f $OUT_DIR/arch/arm/boot/zImage ]; then
    echo "✅ Kernel built successfully. Packing Image..."

    # ضغط الرام ديسك
    if [ -d "$RAMDISK_SRC" ]; then
        pushd $RAMDISK_SRC > /dev/null
        find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../../$RAMDISK_OUT || abort
        popd > /dev/null
    fi

    # إنشاء البوت إيمج
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

    # دمج ملف الـ DT المخصص لسامسونج
    if [ -f "$DT_FILE" ]; then
        cat $DT_FILE >> $OUTPUT_BOOTIMG
        echo -n "SEANDROIDENFORCE" >> $OUTPUT_BOOTIMG
    fi

    echo "-----------------------------------------------"
    echo "🎉 SUCCESS! boot.img ready at: $OUTPUT_BOOTIMG"
    echo "📊 Final Size: $(du -h $OUTPUT_BOOTIMG | cut -f1)"
    echo "-----------------------------------------------"
else
    abort
fi
