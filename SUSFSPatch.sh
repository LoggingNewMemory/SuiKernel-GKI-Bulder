#!/usr/bin/env bash
# SUSFSPatch.sh
# Integrates SUSFS LKM driver from KernelSU-Next into the build tree.

log "Integrating SUSFS LKM..."

# Allow unresolved symbols in modpost for SUSFS LKM (resolved dynamically by ksud at runtime)
export KBUILD_MODPOST_WARN=1

cd "$KSRC"

if [ -d "drivers/kernelsu/susfs" ]; then
    log "Detected SUSFS LKM in drivers/kernelsu/susfs"
    if [ -f "drivers/kernelsu/Kbuild" ] && ! grep -q "susfs" "drivers/kernelsu/Kbuild"; then
        log "Hooking susfs/ into drivers/kernelsu/Kbuild..."
        printf "\nobj-\$(CONFIG_KSU) += susfs/\n" >> "drivers/kernelsu/Kbuild"
    fi
    log "SUSFS LKM integrated successfully!"
elif [ -d "KernelSU-Next/kernel/susfs" ]; then
    log "Detected SUSFS LKM in KernelSU-Next/kernel/susfs"
    if [ -f "KernelSU-Next/kernel/Kbuild" ] && ! grep -q "susfs" "KernelSU-Next/kernel/Kbuild"; then
        log "Hooking susfs/ into KernelSU-Next/kernel/Kbuild..."
        printf "\nobj-\$(CONFIG_KSU) += susfs/\n" >> "KernelSU-Next/kernel/Kbuild"
    fi
    log "SUSFS LKM integrated successfully!"
else
    log "Warning: SUSFS LKM directory not found in KernelSU-Next."
fi
