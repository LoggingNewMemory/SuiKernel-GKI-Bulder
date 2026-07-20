#!/usr/bin/env bash

# AllowShell.sh
# Patches KernelSU core/init.c to allow shell UID 2000 by default

log "Applying AllowShell Patch..."

if [[ -d "$KSRC/KernelSU-Next" ]]; then
    KSU_DIR="$KSRC/KernelSU-Next"
elif [[ -d "$KSRC/KernelSU" ]]; then
    KSU_DIR="$KSRC/KernelSU"
else
    log "[ERROR] KernelSU directory not found!"
    exit 1
fi

INIT_C="$KSU_DIR/kernel/core/init.c"

if [[ -f "$INIT_C" ]]; then
    sed -i 's/bool allow_shell = false;/bool allow_shell = true;/g' "$INIT_C"
    log "✅ allow_shell set to true in $INIT_C"
else
    log "❌ ERROR: $INIT_C not found!"
    exit 1
fi
