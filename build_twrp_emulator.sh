#!/bin/bash
#
# build_twrp_emulator.sh
# Сборка TWRP recovery для x86_64 эмулятора Android (API 22)
#
set -e

# --- Настройки ---
WORKDIR="/workspaces/codespaces-blank/twrp"
SDK_ROOT="/home/codespace/android_sdk"
JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
PYTHON2_PREFIX="/usr/local/python2.7"
MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_omni.git"
MANIFEST_BRANCH="twrp-5.1"
DEVICE_TREE_URL="https://github.com/TeamWin/android_device_emulator_twrpx8664.git"
DEVICE_TREE_PATH="device/emulator/twrpx8664"

echo "=========================================="
echo "  Сборка TWRP для x86_64 эмулятора"
echo "=========================================="
echo "Рабочая директория: $WORKDIR"
echo "SDK: $SDK_ROOT"
echo ""

# --- 1. Системные зависимости ---
echo "[1/7] Установка системных зависимостей..."
sudo apt update
sudo apt install -y git gnupg flex bison build-essential zip curl \
    zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 lib32ncurses-dev \
    libncurses6 lib32z1-dev libgl1-mesa-dev libxml2-utils xsltproc unzip \
    openjdk-8-jdk libssl-dev repo

# --- 2. Python 2.7 ---
echo ""
echo "[2/7] Проверка/установка Python 2.7..."
if ! command -v python2.7 &>/dev/null; then
    echo "Python 2.7 не найден. Собираем из исходников..."
    sudo apt install -y build-essential checkinstall libncurses-dev libssl-dev \
        libsqlite3-dev tk-dev libgdbm-dev libc6-dev libbz2-dev libffi-dev libreadline-dev

    cd /usr/src
    sudo wget -q https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz
    sudo tar xzf Python-2.7.18.tgz
    cd Python-2.7.18
    sudo ./configure --prefix="$PYTHON2_PREFIX"
    sudo make -j$(nproc)
    sudo make install

    sudo ln -sf "$PYTHON2_PREFIX/bin/python2.7" /usr/local/bin/python
else
    echo "Python 2.7 уже установлен."
fi

export PATH="$PYTHON2_PREFIX/bin:$PATH"
if ! python --version 2>&1 | grep -q "2\.7"; then
    echo "ОШИБКА: python не указывает на 2.7"
    exit 1
fi
echo "Python версия: $(python --version 2>&1)"

# --- 3. JAVA_HOME ---
echo ""
echo "[3/7] Настройка JAVA_HOME..."
if [ ! -f "$JAVA_HOME/lib/tools.jar" ]; then
    echo "ОШИБКА: tools.jar не найден в $JAVA_HOME"
    ls /usr/lib/jvm/ 2>/dev/null || true
    exit 1
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
echo "JAVA_HOME = $JAVA_HOME"

# --- 4. Инициализация репозитория TWRP ---
echo ""
echo "[4/7] Инициализация репозитория TWRP (ветка $MANIFEST_BRANCH)..."
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [ ! -d ".repo" ]; then
    repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH"
fi
echo "Синхронизация исходников (20-40 минут)..."
repo sync -j$(nproc) --force-sync

# --- 5. Device tree ---
echo ""
echo "[5/7] Клонирование device tree для x86_64..."
if [ ! -d "$DEVICE_TREE_PATH" ]; then
    git clone "$DEVICE_TREE_URL" "$DEVICE_TREE_PATH"
else
    echo "device tree уже существует."
fi

# --- 6. Заглушки и исправления ---
echo ""
echo "[6/7] Создание недостающих файлов..."

# GPS заглушка
mkdir -p device/common/gps
touch device/common/gps/gps_us_supl.mk

# fstab для goldfish
mkdir -p device/generic/goldfish
cat > device/generic/goldfish/fstab.goldfish << 'EOF'
# Android fstab file.
#<src> <mnt_point> <type> <mnt_flags and options> <fs_mgr_flags>
/dev/block/mtdblock0 /system ext4 ro,barrier=1 wait
/dev/block/mtdblock1 /data ext4 noatime,nosuid,nodev,barrier=1,nomblk_io_submit wait,check
/dev/block/mtdblock2 /cache ext4 noatime,nosuid,nodev wait,check
/devices/platform/goldfish_mmc.0* auto auto defaults voldmanaged=sdcard:auto,noemulatedsd
EOF

# Удаляем проблемный файл зависимостей
rm -f "$DEVICE_TREE_PATH/omni.dependencies"

echo "Файлы-заглушки созданы."

# --- 7. Сборка ---
echo ""
echo "[7/7] Очистка и сборка recovery..."
rm -rf out

source build/envsetup.sh
lunch omni_twrpx8664-eng

echo "Запуск make recoveryimage (30-90 минут)..."
make recoveryimage -j$(nproc)

# --- Проверка результата ---
RECOVERY_IMG="$WORKDIR/out/target/product/twrpx8664/ramdisk-recovery.img"
if [ -f "$RECOVERY_IMG" ]; then
    echo ""
    echo "=========================================="
    echo "  СБОРКА УСПЕШНО ЗАВЕРШЕНА!"
    echo "=========================================="
    ls -lh "$RECOVERY_IMG"
    echo ""
    echo "Образ TWRP: $RECOVERY_IMG"
    echo ""
    echo "Для запуска эмулятора с TWRP используйте команду:"
    echo ""
    echo "  sudo HOME=/home/codespace \\"
    echo "    ANDROID_HOME=$SDK_ROOT \\"
    echo "    ANDROID_SDK_ROOT=$SDK_ROOT \\"
    echo "    ANDROID_AVD_HOME=/home/codespace/.android/avd \\"
    echo "    $SDK_ROOT/emulator/emulator \\"
    echo "    -avd Android_4.4_x86 \\"
    echo "    -skindir $SDK_ROOT/skins \\"
    echo "    -skin nexus_s \\"
    echo "    -ramdisk $RECOVERY_IMG \\"
    echo "    -no-snapshot -gpu swiftshader_indirect -qemu -enable-kvm"
    echo ""
    echo "P.S. Для x86_64-версии специальное ядро (goldfish) не требуется[reference:0]."
else
    echo "ОШИБКА: ramdisk-recovery.img не найден."
    echo "Проверьте вывод make выше."
    exit 1
fi
