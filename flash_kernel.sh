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
    echo "File not found: $INPUT_ZIP"
    exit 1
fi

echo "Using kernel zip: $(basename "$INPUT_ZIP")"
echo "Waiting for device..."
adb wait-for-device

echo "Checking for root access..."
if adb shell "su -c 'echo root_ok'" 2>/dev/null | grep -q 'root_ok'; then
    ROOT_AVAILABLE=true
    echo "[+] Root access detected. Flashing directly on device via su."
else
    ROOT_AVAILABLE=false
    echo "[-] No root access detected (Vanilla kernel)."
fi

if [ "$ROOT_AVAILABLE" = true ]; then
    echo "Pushing kernel to /data/local/tmp/..."
    adb push "$INPUT_ZIP" /data/local/tmp/suikernel-update.zip

    echo "Backing up current boot.img from device..."
    adb shell "su -c '
        SLOT=\$(getprop ro.boot.slot_suffix)
        BOOT_NODE=\"\"
        if [ -e \"/dev/block/by-name/boot\$SLOT\" ]; then
            BOOT_NODE=\"/dev/block/by-name/boot\$SLOT\"
        elif [ -e \"/dev/block/bootdevice/by-name/boot\$SLOT\" ]; then
            BOOT_NODE=\"/dev/block/bootdevice/by-name/boot\$SLOT\"
        fi
        
        if [ -n \"\$BOOT_NODE\" ]; then
            echo \"[*] Dumping boot partition from \$BOOT_NODE...\"
            dd if=\"\$BOOT_NODE\" of=/data/local/tmp/boot_backup.img bs=4M >/dev/null 2>&1
        else
            echo \"Could not find boot partition for backup!\"
            exit 1
        fi
    '"

    echo "Pulling boot_backup.img to host..."
    rm -f boot_backup.img
    adb pull /data/local/tmp/boot_backup.img boot_backup.img || true
    adb shell "su -c 'rm -f /data/local/tmp/boot_backup.img'"

    if [ ! -f boot_backup.img ]; then
        echo "Failed to create or pull boot_backup.img from device!"
        exit 1
    fi
    echo "Boot partition backed up to boot_backup.img"

    echo "Flashing via root shell..."
    # Execute the AnyKernel3 update-binary script directly with BOOTMODE=true
    adb shell "su -c '
        echo \"[*] Cleaning up old tmp dir...\"
        rm -rf /data/local/tmp/ak3-tmp
        mkdir -p /data/local/tmp/ak3-tmp
        
        echo \"[*] Extracting kernel zip...\"
        unzip -oq /data/local/tmp/suikernel-update.zip -d /data/local/tmp/ak3-tmp >/dev/null 2>&1
        
        echo \"[*] Executing AnyKernel3 Flasher...\"
        cd /data/local/tmp/ak3-tmp
        export BOOTMODE=true
        # Redirecting to a file prevents the /proc/self/fd/1 \"No such device or address\" pseudo-terminal error
        if ! sh META-INF/com/google/android/update-binary 2 1 /data/local/tmp/suikernel-update.zip > flash_log.txt 2>&1; then
            echo \"Error: AnyKernel3 Flasher failed!\"
            cat flash_log.txt
            exit 1
        fi
        
        echo \"[*] Cleaning up device...\"
        rm -rf /data/local/tmp/ak3-tmp
        rm -f /data/local/tmp/suikernel-update.zip
        
        echo \"Kernel flashed successfully!\"
    '"

    echo "Done! Rebooting device now..."
    adb reboot
else
    echo "This device is unrooted. We will flash via ADB Sideload in sideload."
    echo "Rebooting device to sideload mode..."
    adb reboot sideload
    
    echo "=========================================================="
    echo " PLEASE PUT YOUR DEVICE IN SIDELOAD MODE NOW"
    echo " In TWRP: Go to Advanced -> ADB Sideload -> Swipe to Start"
    echo "=========================================================="
    echo "Waiting for device to enter 'sideload' mode..."
    
    # Wait specifically for the sideload state
    while true; do
        STATE=$(adb get-state 2>/dev/null || true)
        if [ "$STATE" = "sideload" ]; then
            break
        fi
        sleep 2
    done
    
    echo "Device is now in sideload mode! Sideloading $INPUT_ZIP..."
    adb sideload "$INPUT_ZIP"
fi
