#!/usr/bin/env bash

# SuiKernel ADB Auto-Flasher
# Usage: ./flash_kernel.sh /path/to/downloaded-artifact.zip

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path_to_zip_artifact>"
    exit 1
fi

INPUT_ZIP="$1"

if [ ! -f "$INPUT_ZIP" ]; then
    echo "❌ File not found: $INPUT_ZIP"
    exit 1
fi

echo "📦 Extracting artifact zip locally..."
TMP_DIR=$(mktemp -d)
unzip -q "$INPUT_ZIP" -d "$TMP_DIR"

# Find the actual AnyKernel zip inside the extracted artifact
REAL_ZIP=$(find "$TMP_DIR" -name "*.zip" | head -n 1)

if [ -z "$REAL_ZIP" ]; then
    echo "❌ No actual kernel .zip found inside the artifact!"
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "✅ Found real kernel zip: $(basename "$REAL_ZIP")"
echo "📱 Waiting for device..."
adb wait-for-device

echo "📤 Pushing kernel to /data/local/tmp/..."
adb push "$REAL_ZIP" /data/local/tmp/suikernel-update.zip

echo "⚙️ Flashing via root shell..."
# Execute the AnyKernel3 update-binary script directly with BOOTMODE=true
adb shell "su -c '
    echo \"[*] Cleaning up old tmp dir...\"
    rm -rf /data/local/tmp/ak3-tmp
    mkdir -p /data/local/tmp/ak3-tmp
    
    echo \"[*] Extracting kernel zip...\"
    unzip -oq /data/local/tmp/suikernel-update.zip -d /data/local/tmp/ak3-tmp
    
    echo \"[*] Executing AnyKernel3 Flasher...\"
    cd /data/local/tmp/ak3-tmp
    export BOOTMODE=true
    # Redirecting to a file prevents the /proc/self/fd/1 \"No such device or address\" pseudo-terminal error
    sh META-INF/com/google/android/update-binary 2 1 /data/local/tmp/suikernel-update.zip > flash_log.txt 2>&1
    cat flash_log.txt
    
    echo \"[*] Cleaning up device...\"
    rm -rf /data/local/tmp/ak3-tmp
    rm -f /data/local/tmp/suikernel-update.zip
    
    echo \"✅ Kernel flashed successfully!\"
'"

echo "🧹 Cleaning up local temp files..."
rm -rf "$TMP_DIR"

echo "🎉 Done! Rebooting device now..."
adb reboot
