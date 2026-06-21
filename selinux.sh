#!/usr/bin/env bash
# selinux.sh
# SELinux rule injections for SuiKernel modules
# Sourced by build.sh — must be called from inside $KSRC
# Author: Kanagawa Yamada

SELINUX_RULES_C="drivers/kernelsu/selinux/rules.c"

# Sanity check — fail loudly if the target file isn't present
if [[ ! -f "$SELINUX_RULES_C" ]]; then
    error "selinux.sh: $SELINUX_RULES_C not found. KernelSU not installed yet?"
    exit 1
fi

inject_selinux() {
    local label="$1"
    local rules="$2"

    log "Injecting ${label} SELinux rules..."
    sed -i "/rcu_assign_pointer(selinux_state.policy, pol);/i ${rules}" \
        "$SELINUX_RULES_C"
}

# ---------------------------------------------------------------------------
# Tenebrion — allow kernel to read screen state + write cpuset
# ---------------------------------------------------------------------------
inject_selinux "Tenebrion" \
    '    ksu_allow(db, "kernel", "sysfs_leds", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "file", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_backlight", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_backlight", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_backlight", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_backlight", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_backlight", "file", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_drm", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_drm", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_drm", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_drm", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_drm", "file", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_type", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_type", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_type", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_type", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_type", "file", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Anya Thermal — allow kernel to write thermal zone mode
# ---------------------------------------------------------------------------
inject_selinux "Anya Thermal" \
    '    ksu_allow(db, "kernel", "sysfs_therm", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "write");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "open");\n'

# ---------------------------------------------------------------------------
# NTSYNC — Allow kernel background worker to auto-chmod and spoof as gpu_device
#          Explicitly allow Winlator to RW the spoofed device
# ---------------------------------------------------------------------------
inject_selinux "NTSYNC" \
    '    ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
    ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n'

# ---------------------------------------------------------------------------
# Ochinai Inaho Audio — cpuset read + dac_override
# ---------------------------------------------------------------------------
inject_selinux "Ochinai Inaho Audio" \
    '    ksu_allow(db, "kernel", "kernel", "capability", "dac_override");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "search");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "read");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "open");\n'

# ---------------------------------------------------------------------------
# Schedutil Enforcer — allow kernel to write to cpufreq policy nodes
# ---------------------------------------------------------------------------
inject_selinux "Schedutil Enforcer" \
    '    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "write");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "getattr");\n' 


# ---------------------------------------------------------------------------
# Ayunda Risu Native Root Exec — allow init to exec into the KernelSU domain
#
# The execution path is:
#   init (RC stanza injected by KernelSU) → exec u:r:su:s0 root
#       → /system/bin/sh -c "<cmd>"
#
# For this to work init needs:
#   • transition    — to enter the su domain via exec
#   • dyntransition — for setcon-style transitions init may use
# The su domain (KERNEL_SU_DOMAIN) is already fully permissive per rules.c,
# so no additional rules are needed there.
#
# We also keep kernel→shell_exec execute rules for the UMH fallback path in
# ayunda_risu_native_root_exec.c (used post-boot when RC stream is closed).
# ---------------------------------------------------------------------------
inject_selinux "Ayunda Risu Native Root Exec" \
    '    ksu_allow(db, "init", KERNEL_SU_DOMAIN, "process", "transition");\n\
    ksu_allow(db, "init", KERNEL_SU_DOMAIN, "process", "dyntransition");\n\
    ksu_allow(db, "init", KERNEL_SU_DOMAIN, "process", "noatsecure");\n\
    ksu_allow(db, "init", KERNEL_SU_FILE, "file", "execute");\n\
    ksu_allow(db, "init", KERNEL_SU_FILE, "file", "read");\n\
    ksu_allow(db, "init", KERNEL_SU_FILE, "file", "open");\n\
    ksu_allow(db, "init", "shell_exec", "file", "execute");\n\
    ksu_allow(db, "init", "shell_exec", "file", "execute_no_trans");\n\
    ksu_allow(db, "init", "shell_exec", "file", "read");\n\
    ksu_allow(db, "init", "shell_exec", "file", "open");\n\
    ksu_allow(db, "init", "shell_exec", "file", "entrypoint");\n\
    ksu_allow(db, "kernel", KERNEL_SU_DOMAIN, "process", "transition");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "execute");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "execute_no_trans");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "read");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "open");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "getattr");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "map");\n'

log "✅ All SELinux rules injected successfully"