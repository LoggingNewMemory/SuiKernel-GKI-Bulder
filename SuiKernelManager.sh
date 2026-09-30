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
read -r -d '' INJECT_LOGIC << 'EOF'
	char sui_pkg[KSU_MAX_PACKAGE_NAME];
	if (get_pkg_from_apk_path(sui_pkg, path) >= 0) {
		if (strncmp(sui_pkg, "kanagawa.yamada.suikernel.manager", 33) == 0) {
			pr_info("SuiKernel: Manager detected! Granting native rights.\n");
			return true;
		}
	}
EOF

# Check if already patched
if grep -q "kanagawa.yamada.suikernel.manager" "$APK_SIGN_FILE"; then
    echo "[!] Already patched!"
    exit 0
fi

# Insert the logic right after bool is_manager_apk(char *path) {
export INJECT_LOGIC
awk '
/^bool is_manager_apk\(char \*path\)/ {
    print $0
    getline
    print $0
    print ENVIRON["INJECT_LOGIC"]
    next
}
{ print $0 }
' "$APK_SIGN_FILE" > "$APK_SIGN_FILE.tmp" && mv "$APK_SIGN_FILE.tmp" "$APK_SIGN_FILE"

echo "[+] Patch applied successfully to KSUN Manager Identity!"
