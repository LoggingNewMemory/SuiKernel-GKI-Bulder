#!/usr/bin/env bash
# selinux.sh
# SELinux rule injections for SuiKernel modules
# Sourced by build.sh — must be called from inside $KSRC
# Author: Kanagawa Yamada

if [[ -f "drivers/kernelsu/selinux/rules.c" ]]; then
    SELINUX_RULES_C="drivers/kernelsu/selinux/rules.c"
elif [[ -f "drivers/YamadaKSUCore/selinux/rules.c" ]]; then
    SELINUX_RULES_C="drivers/YamadaKSUCore/selinux/rules.c"
else
    error "selinux.sh: KernelSU or YamadaKSUCore not found!"
    exit 1
fi

inject_selinux() {
    local label="$1"
    local rules="$2"

    log "Injecting ${label} SELinux rules..."
    if grep -q 'ksu_policydb_fixup_len(db, "apply_kernelsu_rules");' "$SELINUX_RULES_C"; then
        sed -i -e "0,/ksu_policydb_fixup_len(db, \"apply_kernelsu_rules\");/ {
            /ksu_policydb_fixup_len(db, \"apply_kernelsu_rules\");/i ${rules}
        }" "$SELINUX_RULES_C"
    else
        sed -i -e "0,/rcu_assign_pointer(selinux_state.policy, pol);/ {
            /rcu_assign_pointer(selinux_state.policy, pol);/i ${rules}
        }" "$SELINUX_RULES_C"
    fi
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
    ksu_allow(db, "kernel", "sysfs", "file", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "search");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "write");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "read");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "write");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "open");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n'

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
# Ochinai Inaho Audio — dac_override
# ---------------------------------------------------------------------------
inject_selinux "Ochinai Inaho Audio" \
    '    ksu_allow(db, "kernel", "kernel", "capability", "dac_override");\n'

# ---------------------------------------------------------------------------
# Airani Iofifteen CPUSet — cpuset read/write
# ---------------------------------------------------------------------------
inject_selinux "Airani Iofifteen CPUSet" \
    '    ksu_allow(db, "kernel", "kernel", "capability", "dac_read_search");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "search");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "write");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "read");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "write");\n\
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
# Moona Hoshinova ZRAM — allow kernel to write to page-cluster and vma_ra_enabled
# ---------------------------------------------------------------------------
inject_selinux "Moona Hoshinova ZRAM" \
    '    ksu_allow(db, "kernel", "proc_page_cluster", "file", "read");\n\
    ksu_allow(db, "kernel", "proc_page_cluster", "file", "write");\n\
    ksu_allow(db, "kernel", "proc_page_cluster", "file", "open");\n\
    ksu_allow(db, "kernel", "proc_page_cluster", "file", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs", "file", "write");\n'

# ---------------------------------------------------------------------------
# SuiKernel Manager Config Storage & Execution
# ---------------------------------------------------------------------------
inject_selinux "SuiKernel Manager Storage" \
    '    ksu_allow(db, "kernel", "system_data_root_file", "dir", "search");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "dir", "read");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "dir", "open");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "dir", "write");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "dir", "add_name");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "dir", "remove_name");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "read");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "write");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "open");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "getattr");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "create");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "unlink");\n\
    ksu_allow(db, "kernel", "system_data_root_file", "file", "setattr");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "search");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "read");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "open");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "write");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "add_name");\n\
    ksu_allow(db, "kernel", "system_data_file", "dir", "remove_name");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "read");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "write");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "open");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "getattr");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "create");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "unlink");\n\
    ksu_allow(db, "kernel", "system_data_file", "file", "setattr");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "search");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "read");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "open");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "write");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "add_name");\n\
    ksu_allow(db, "kernel", "app_data_file", "dir", "remove_name");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "read");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "write");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "open");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "getattr");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "create");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "unlink");\n\
    ksu_allow(db, "kernel", "app_data_file", "file", "setattr");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "read");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "open");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "getattr");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "execute");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "execute_no_trans");\n\
    ksu_allow(db, "kernel", "shell_exec", "file", "map");\n\
    ksu_allow(db, "kernel", "toolbox_exec", "file", "read");\n\
    ksu_allow(db, "kernel", "toolbox_exec", "file", "open");\n\
    ksu_allow(db, "kernel", "toolbox_exec", "file", "getattr");\n\
    ksu_allow(db, "kernel", "toolbox_exec", "file", "execute");\n\
    ksu_allow(db, "kernel", "toolbox_exec", "file", "execute_no_trans");\n\
    ksu_allow(db, "kernel", "toolbox_exec", "file", "map");\n\
    ksu_allow(db, "kernel", "system_file", "file", "execute_no_trans");\n\
    ksu_allow(db, "kernel", "system_file", "file", "read");\n\
    ksu_allow(db, "kernel", "system_file", "file", "open");\n\
    ksu_allow(db, "kernel", "system_file", "file", "getattr");\n\
    ksu_allow(db, "kernel", "system_file", "file", "map");\n\
    ksu_allow(db, "kernel", "untrusted_app", "fd", "use");\n\
    ksu_allow(db, "kernel", "untrusted_app", "fifo_file", "read");\n\
    ksu_allow(db, "kernel", "untrusted_app", "fifo_file", "write");\n\
    ksu_allow(db, "kernel", "untrusted_app", "fifo_file", "open");\n\
    ksu_allow(db, "kernel", "untrusted_app", "fifo_file", "getattr");\n\
    ksu_allow(db, "kernel", "untrusted_app_all", "fd", "use");\n\
    ksu_allow(db, "kernel", "untrusted_app_all", "fifo_file", "read");\n\
    ksu_allow(db, "kernel", "untrusted_app_all", "fifo_file", "write");\n\
    ksu_allow(db, "kernel", "untrusted_app_all", "fifo_file", "open");\n\
    ksu_allow(db, "kernel", "untrusted_app_all", "fifo_file", "getattr");\n\
    ksu_allow(db, "kernel", "untrusted_app_29", "fd", "use");\n\
    ksu_allow(db, "kernel", "untrusted_app_29", "fifo_file", "read");\n\
    ksu_allow(db, "kernel", "untrusted_app_29", "fifo_file", "write");\n\
    ksu_allow(db, "kernel", "untrusted_app_30", "fd", "use");\n\
    ksu_allow(db, "kernel", "untrusted_app_30", "fifo_file", "read");\n\
    ksu_allow(db, "kernel", "untrusted_app_30", "fifo_file", "write");\n\
    ksu_allow(db, "kernel", "untrusted_app_32", "fd", "use");\n\
    ksu_allow(db, "kernel", "untrusted_app_32", "fifo_file", "read");\n\
    ksu_allow(db, "kernel", "untrusted_app_32", "fifo_file", "write");\n\
    ksu_allow(db, "kernel", "devpts", "chr_file", "read");\n\
    ksu_allow(db, "kernel", "devpts", "chr_file", "write");\n\
    ksu_allow(db, "kernel", "devpts", "chr_file", "open");\n\
    ksu_allow(db, "kernel", "devpts", "chr_file", "ioctl");\n\
    ksu_allow(db, "kernel", "devpts", "chr_file", "getattr");\n\
    ksu_allow(db, "kernel", "kernel", "capability", "dac_override");\n\
    ksu_allow(db, "kernel", "kernel", "capability", "dac_read_search");\n\
    ksu_allow(db, "kernel", "kernel", "capability", "fowner");\n\
    ksu_allow(db, "kernel", "kernel", "capability", "fsetid");\n\
    ksu_allow(db, "kernel", "kernel", "capability", "sys_admin");\n'

log "All SELinux rules injected successfully"