#!/bin/bash
log "Cloning and applying SUSFS patches..."
cd "$KSRC"
rm -rf "$workdir/susfs"
git clone --depth=1 -q https://gitlab.com/simonpunk/susfs4ksu -b gki-android12-5.10 "$workdir/susfs"
SUSFS_PATCHES="$workdir/susfs/kernel_patches"

cp -R "$SUSFS_PATCHES"/fs/* ./fs/
cp -R "$SUSFS_PATCHES"/include/* ./include/
patch -p1 < "$SUSFS_PATCHES"/50_add_susfs_in_gki-android12-5.10.patch || log "Warning: Kernel patch applied with fuzz or failed."

log "Applying SUSFS patch to KernelSU-Next..."
cd KernelSU-Next
patch -p1 < "$SUSFS_PATCHES/KernelSU/10_enable_susfs_for_ksu.patch" || log "Warning: KSU patch applied with fuzz or failed."
cd ..

log "SUSFS integrated successfully!"
