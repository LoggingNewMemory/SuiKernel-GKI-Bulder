#!/usr/bin/env bash
# PavoliaReinePatch.sh
# Applies the Pavolia Reine Android Property Injector integration to KernelSU

log "Applying Pavolia Reine KernelSU integration patch..."

if [ -d "drivers/kernelsu" ]; then
    cd drivers/kernelsu
    patch -p1 < "$workdir/pavolia_reine_ksu.patch"
    cd -
else
    log "Error: drivers/kernelsu not found. KernelSU must be cloned before applying this patch."
fi
