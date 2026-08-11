#!/bin/bash

# Добавляем данные
export DEVICE="munch"
export VERSION="1.0.0"
export PREFIX="s"
export TYPE="stable"
export BUILD_TYPE="Stable"
#export TGTOKEN=bot_token
#export CHAT_ID=chat_id

# Начало отсчета времени выполнения скрипта
start_time=$(date +%s)

# Удаление каталога "out", если он существует
rm -rf out

# Основной каталог
MAINPATH=/home/runner/work/kernel_xiaomi_sm8250/kernel_xiaomi_sm8250 # измените, если необходимо

# Каталог ядра
KERNEL_DIR=$MAINPATH
KERNEL_PATH=$KERNEL_DIR/kernel_xiaomi_sm8250

BRANCH=$(git branch --show-current)

# Каталоги компиляторов
CLANG_DIR=$KERNEL_DIR/clang21

# Проверка и клонирование, если необходимо
check_and_wget() {
    local dir=$1
    local repo=$2

    if [ ! -d "$dir" ]; then
        echo "Папка $dir не существует. Клонирование $repo."
        mkdir $dir
        cd $dir
        wget $repo &> /dev/null
        tar -zxvf clang-r547379.tar.gz &> /dev/null
        rm -rf clang-r547379.tar.gz
        echo "Done."
        cd ../kernel_xiaomi_sm8250
    fi
}

# Клонирование инструментов компиляции, если они не существуют
check_and_wget $CLANG_DIR https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz

# Установка переменных PATH
PATH=$CLANG_DIR/bin:$PATH
export PATH
export ARCH=arm64

# Каталог для сборки Perf+
PERF_DIR="$KERNEL_DIR/perf"

# Создание каталога Perf+, если его нет
if [ ! -d "$PERF_DIR" ]; then
    mkdir -p "$PERF_DIR"
    
    # Проверка и клонирование Anykernel, если Perf+ не существует
    if [ ! -d "$PERF_DIR/Anykernel" ]; then
        git clone https://github.com/olzhas0986/Anykernel3.git -b perf "$PERF_DIR/Anykernel"
        
        # Перемещение всех файлов из Anykernel в Perf+
        mv "$PERF_DIR/Anykernel/"* "$PERF_DIR/"
        
        # Удаление папки Anykernel
        rm -rf "$PERF_DIR/Anykernel"
    fi
else
    # Если папка Perf+ существует, проверить наличие .git и удалить, если есть
    if [ -d "$PERF_DIR/.git" ]; then
        rm -rf "$PERF_DIR/.git"
    fi
fi

# Экспорт переменных среды
export IMGPATH="$PERF_DIR/Image"
export DTBPATH="$PERF_DIR/dtb"
export DTBOPATH="$PERF_DIR/dtbo.img"
export KBUILD_BUILD_USER="veedz"
export KBUILD_BUILD_HOST="@github.com"

# Запись времени сборки
PERF_BUILD_DATE=$(date '+%Y-%m-%d_%H-%M-%S')

# Каталог для результатов сборки
output_dir=out

# Конфигурация ядра
 make O="$output_dir" \
            vendor/${DEVICE}_defconfig
 for config in \
    'CONFIG_CFG80211=y' \
    'CONFIG_MAC80211=y' \
    'CONFIG_MAC80211_RC_MINSTREL_VHT=y' \
    'CONFIG_MAC80211_MESH=y' \
    'CONFIG_WLAN=y' \
    'CONFIG_ATH_COMMON=m' \
    'CONFIG_ATH9K_HW=m' \
    'CONFIG_ATH9K_COMMON=m' \
    'CONFIG_ATH5K=m' \
    'CONFIG_ATH9K=m' \
    'CONFIG_ATH9K_AHB=y' \
    'CONFIG_ATH9K_DYNACK=y' \
    'CONFIG_ATH9K_WOW=y' \
    'CONFIG_ATH9K_CHANNEL_CONTEXT=y' \
    'CONFIG_ATH9K_HTC=m' \
    'CONFIG_ATH9K_HWRNG=y' \
    'CONFIG_CARL9170=m' \
    'CONFIG_CARL9170_HWRNG=y' \
    'CONFIG_ATH6KL=m' \
    'CONFIG_ATH6KL_SDIO=m' \
    'CONFIG_ATH6KL_USB=m' \
    'CONFIG_AR5523=m' \
    'CONFIG_ATH10K=m' \
    'CONFIG_ATH10K_PCI=m' \
    'CONFIG_ATH10K_AHB=y' \
    'CONFIG_ATH10K_SDIO=m' \
    'CONFIG_ATH10K_USB=m' \
    'CONFIG_ATH10K_SNOC=m' \
    'CONFIG_WCN36XX=m' \
    'CONFIG_WCN36XX_DEBUGFS=y' \
    'CONFIG_MT7601U=m' \
    'CONFIG_MT76x0U=m' \
    'CONFIG_MT76x2E=m' \
    'CONFIG_MT76x2U=m' \
    'CONFIG_RTL8180=m' \
    'CONFIG_RTL8187=m' \
    'CONFIG_RTL8XXXU=m' \
    'CONFIG_RTL8XXXU_UNTESTED=y' \
    'CONFIG_MODULE_FORCE_LOAD=y' \
    'CONFIG_MODULE_UNLOAD=y' \
    'CONFIG_MODULE_FORCE_UNLOAD=y'
 do
    if grep -qx "$config" "$output_dir/.config"; then
        echo "[OK] $config"
    else
        echo "[ERROR] Missing: $config"
        exit 1
    fi
done
    
    # Компиляция ядра
    make -j $(nproc) \
                O="$output_dir" \
                CC="ccache clang" \
                HOSTCC=gcc \
                LD=ld.lld \
                AS=llvm-as \
                AR=llvm-ar \
                NM=llvm-nm \
                OBJCOPY=llvm-objcopy \
                OBJDUMP=llvm-objdump \
                STRIP=llvm-strip \
                LLVM=1 \
                LLVM_IAS=1 \
                V=$VERBOSE 2>&1 | tee build.log
                
# Copy kernel modules (.ko)
MODULES_DIR="$PERF_DIR/modules/vendor/lib/modules"

mkdir -p "$MODULES_DIR"

find "$output_dir" -type f -name "*.ko" \
    -exec cp -f {} "$MODULES_DIR/" \;

echo "Kernel modules copied:"
find "$MODULES_DIR" -type f -name "*.ko"

# Предполагается, что переменная DTS установлена ранее в скрипте
find $DTS -name '*.dtb' -exec cat {} + > $DTBPATH
find $DTS -name 'Image' -exec cat {} + > $IMGPATH
find $DTS -name 'dtbo.img' -exec cat {} + > $DTBOPATH

# Завершение отсчета времени выполнения скрипта
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

cd "$KERNEL_PATH"

# Проверка успешности сборки
if grep -q -E "Ошибка 2|Error 2" build.log; then
    cd "$KERNEL_PATH"
    echo "Ошибка: Сборка завершилась с ошибкой"

    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendMessage \
    -d chat_id="$CHAT_ID" \
    -d text="Ошибка в компиляции!"

    curl -s -X POST "https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=$CHAT_ID" \
    -F document=@"./build.log"
else
    echo "Общее время выполнения: $elapsed_time секунд"
    # Перемещение в каталог Perf+ и создание архива
    cd "$PERF_DIR"
    7z a -mx9 perf-$DEVICE-$PERF_BUILD_DATE.zip * -x!*.zip
    
    curl -s -X POST https://api.telegram.org/bot$TGTOKEN/sendMessage \
    -d chat_id="$CHAT_ID" \
    -d text="Компиляция завершилась успешно! Время выполнения: $elapsed_time секунд"

    curl -s -X POST "https://api.telegram.org/bot$TGTOKEN/sendDocument?chat_id=$CHAT_ID" \
    -F document=@"./perf-$DEVICE-$PERF_BUILD_DATE.zip" \
    -F caption="perf ${VERSION}${PREFIX} (${BUILD_TYPE}) branch: ${BRANCH}"

    rm -rf perf-$DEVICE-$PERF_BUILD_DATE.zip
fi
