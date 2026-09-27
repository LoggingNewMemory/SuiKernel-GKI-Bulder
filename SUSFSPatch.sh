#!/bin/bash
log "Cloning and applying SUSFS patches..."
cd "$KSRC"
rm -rf "$workdir/susfs"
git clone --depth=1 -q https://gitlab.com/simonpunk/susfs4ksu -b gki-android12-5.10 "$workdir/susfs"
SUSFS_PATCHES="$workdir/susfs/kernel_patches"

cp -R "$SUSFS_PATCHES"/fs/* ./fs/
cp -R "$SUSFS_PATCHES"/include/* ./include/
patch -p1 < "$SUSFS_PATCHES"/50_add_susfs_in_gki-android12-5.10.patch || log "Warning: Kernel patch applied with fuzz or failed."

log "Injecting SUSFS Kconfig options into KernelSU-Next..."
cat << 'EOF' >> KernelSU-Next/kernel/Kconfig

menu "KernelSU - SUSFS"
config KSU_SUSFS
	bool "KernelSU addon - SUSFS"
	depends on KSU
	default y

config KSU_SUSFS_SUS_PATH
	bool "Enable to hide suspicious path"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_MOUNT
	bool "Enable to hide suspicious mounts"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_KSTAT
	bool "Enable to spoof suspicious kstat"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SPOOF_UNAME
	bool "Enable to spoof uname"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_ENABLE_LOG
	bool "Enable logging susfs log to kernel"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
	bool "Enable to automatically hide ksu and susfs symbols from /proc/kallsyms"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	bool "Enable to spoof /proc/bootconfig (gki) or /proc/cmdline (non-gki)"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_OPEN_REDIRECT
	bool "Enable to redirect a path to be opened with another path"
	depends on KSU_SUSFS
	default y

config KSU_SUSFS_SUS_MAP
	bool "Enable to hide some mmapped real file from different proc maps interfaces"
	depends on KSU_SUSFS
	default y
endmenu
EOF

log "SUSFS integrated successfully!"
