#!/bin/bash
# SuiKernelManager.sh - Patches KSUN to work alongside SuiKernel Manager

KERNEL_DIR="$1"
if [ -z "$KERNEL_DIR" ]; then
    echo "Usage: ./SuiKernelManager.sh <kernel_directory>"
    exit 1
fi

KSUN_DIR="$KERNEL_DIR/KernelSU-Next"
APK_SIGN_FILE="$KSUN_DIR/kernel/manager/apk_sign.c"

echo "[+] Patching KernelSU-Next to accept SuiKernel Manager as a secondary Manager in $KSUN_DIR"

if [ ! -f "$APK_SIGN_FILE" ]; then
    echo "[-] Cannot find $APK_SIGN_FILE"
    exit 0
fi

# We will inject the check into is_manager_apk()
INJECT_LOGIC="	if (strncmp(pkg, \"kanagawa.yamada.suikernel.manager\", 33) == 0) {\n		pr_info(\"SuiKernel: Manager detected! Granting native rights.\\\\n\");\n		return true;\n	}"

# Check if already patched
if grep -q "kanagawa.yamada.suikernel.manager" "$APK_SIGN_FILE"; then
    echo "[!] Already patched!"
    exit 0
fi

# Insert the logic right after getting the package name
sed -i '/if (get_pkg_from_apk_path(pkg, path) < 0) {/,/}/a \'"\n$INJECT_LOGIC\n" "$APK_SIGN_FILE"

echo "[+] Patch applied successfully to KSUN Manager Identity!"
