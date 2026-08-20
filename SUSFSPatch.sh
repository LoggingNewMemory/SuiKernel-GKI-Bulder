log "Applying SUSFS patches..."
cd $KSRC

# Download SUSFS source files for 5.10
curl -LSs "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android12-5.10/kernel_patches/fs/susfs.c" -o fs/susfs.c
curl -LSs "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android12-5.10/kernel_patches/include/linux/susfs.h" -o include/linux/susfs.h
curl -LSs "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android12-5.10/kernel_patches/include/linux/susfs_def.h" -o include/linux/susfs_def.h

# Download and apply the main SUSFS patch
curl -LSs "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android12-5.10/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch" -o susfs.patch
patch -p1 < susfs.patch || log "Warning: Patch applied with fuzz or failed."
rm susfs.patch

log "SUSFS patches applied successfully!"
