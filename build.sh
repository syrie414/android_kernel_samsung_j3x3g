#!/bin/bash

# --- 1. إعدادات الهوية والبيئة ---
export ARCH=arm
export KBUILD_BUILD_USER="imad"
export KBUILD_BUILD_HOST="Linkit2me-Lab"

# مسار المترجم (التأكد من المسار النسبي والمطلق)
TOOLCHAIN_PATH=$PWD/toolchain/bin/arm-linux-androideabi-
export CROSS_COMPILE=$TOOLCHAIN_PATH

# الملفات النشطة حالياً
BASE_CONFIG=j3x3g-dt_defconfig
REC_CONFIG=recovery.config

# --- 2. تنظيف البيئة ---
echo "--- Cleaning build directory ---"
rm -rf out
mkdir -p out
make O=out mrproper

# --- 3. دمج الإعدادات (Base + Recovery) ---
echo "--- Merging configs: $BASE_CONFIG + $REC_CONFIG ---"
if [ ! -f arch/arm/configs/$BASE_CONFIG ]; then
    echo "ERROR: Base config not found!" && exit 1
fi

# بناء الكونسفج الأساسي أولاً
make O=out $BASE_CONFIG

# دمج إعدادات الريكفري يدوياً لضمان التطبيق الفعلي
if [ -f arch/arm/configs/$REC_CONFIG ]; then
    echo "Applying Recovery Config patches..."
    cat arch/arm/configs/$REC_CONFIG >> out/.config
    # إعادة ترتيب الـ config لتجنب التعارضات
    make O=out oldconfig
else
    echo "WARNING: Recovery config not found, skipping merge."
fi

# التحقق من تطبيق الاسم الجديد أو أي خيار مهم
grep "CONFIG_LOCALVERSION" out/.config || true

# --- 4. بدء البناء الفعلي (Kernel + DTBs) ---
echo "--- Starting Compilation for J320H (Kernel + DTBs) ---"
# إضافة KCFLAGS لتجنب أخطاء تعريف المتغيرات المتكررة في النسخ الحديثة من GCC
make O=out KCFLAGS="-fcommon" HOSTCFLAGS="-fcommon" -j$(nproc --all) zImage dtbs

# --- 5. النتيجة النهائية والتحقق ---
echo "-----------------------------------------------"
if [ -f out/arch/arm/boot/zImage ]; then
    echo "SUCCESS! Kernel (zImage) is ready."
    
    # البحث عن ملف الـ DTB الناتج (مهم جداً للريكفري)
    # غالباً ما يكون في مسار out/arch/arm/boot/dts/
    DTB_FILE=$(find out/arch/arm/boot/dts/ -name "*.dtb" | head -n 1)
    
    if [ -n "$DTB_FILE" ]; then
        echo "SUCCESS! DTB File found: $DTB_FILE"
    else
        echo "WARNING: Kernel built but no DTB file found! Check your dts source."
    fi
    
    echo "Location: out/arch/arm/boot/zImage"
    du -h out/arch/arm/boot/zImage
else
    echo "BUILD FAILED! Check the logs for errors."
    exit 1
fi
echo "-----------------------------------------------"
