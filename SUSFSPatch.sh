#!/usr/bin/env bash
# SUSFSPatch.sh
# Integrates SUSFS LKM driver from KernelSU-Next into the build tree.

log "Integrating SUSFS LKM..."

# Allow unresolved symbols in modpost for SUSFS LKM (resolved dynamically by ksud at runtime)
export KBUILD_MODPOST_WARN=1

cd "$KSRC"

KBUILD_FILE=""
if [ -d "drivers/kernelsu/susfs" ] && [ -f "drivers/kernelsu/Kbuild" ]; then
    KBUILD_FILE="drivers/kernelsu/Kbuild"
elif [ -d "KernelSU-Next/kernel/susfs" ] && [ -f "KernelSU-Next/kernel/Kbuild" ]; then
    KBUILD_FILE="KernelSU-Next/kernel/Kbuild"
fi

if [ -n "$KBUILD_FILE" ]; then
    if ! grep -q "susfs" "$KBUILD_FILE"; then
        log "Hooking susfs/ into $KBUILD_FILE..."
        printf "\nobj-\$(CONFIG_KSU) += susfs/\n" >> "$KBUILD_FILE"
    fi
    log "SUSFS LKM integrated successfully!"
else
    log "Warning: SUSFS LKM directory not found in KernelSU-Next."
fi
