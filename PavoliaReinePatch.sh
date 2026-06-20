#!/usr/bin/env bash
# PavoliaReinePatch.sh
# Applies the Pavolia Reine Android Property Injector integration to KernelSU

log "Applying Pavolia Reine KernelSU integration..."

if [ ! -d "drivers/kernelsu" ]; then
    log "Error: drivers/kernelsu not found. KernelSU must be cloned before applying this patch."
    exit 1
fi

python3 - << 'EOF'
import sys

filepath = "drivers/kernelsu/kernel/runtime/ksud_integration.c"

with open(filepath, "r") as f:
    content = f.read()

# 1. Add definitions
target1 = "// clang-format on\n"
replacement1 = target1 + """
char pavolia_rc_buf[4096] = {0};
size_t pavolia_rc_len = 0;
ssize_t pavolia_rc_pos = 0;

void ksu_pavolia_add_prop(const char *prop, const char *val) {
    char buf[256];
    /* Using sys.boot_completed to inject when OS is ready */
    snprintf(buf, sizeof(buf), "\\non property:sys.boot_completed=1\\n    setprop %s \\"%s\\"\\n", prop, val);
    strlcat(pavolia_rc_buf, buf, sizeof(pavolia_rc_buf));
    pavolia_rc_len = strlen(pavolia_rc_buf);
}
EXPORT_SYMBOL(ksu_pavolia_add_prop);
"""
content = content.replace(target1, replacement1)

# 2. Add append_pavolia_rc to read_proxy
target2 = """    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos < module_rc_len)
        goto append_module_rc;"""
replacement2 = target2 + """
    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos < pavolia_rc_len)
        goto append_pavolia_rc;"""
content = content.replace(target2, replacement2)

target3 = "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len) {"
replacement3 = "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len) {"
content = content.replace(target3, replacement3)

target4 = """            pr_info("read_proxy: module append done\\n");
            free_module_rc();
        }
    }

    return ret;"""
replacement4 = """            pr_info("read_proxy: module append done\\n");
            free_module_rc();
        }
    }

append_pavolia_rc:
    if (pavolia_rc_pos < pavolia_rc_len && (size_t)ret < count) {
        size_t append_count = pavolia_rc_len - pavolia_rc_pos;
        if (append_count > count - ret)
            append_count = count - ret;
        if (copy_to_user(buf + ret, pavolia_rc_buf + pavolia_rc_pos, append_count)) {
            pr_info("read_proxy: pavolia append error, totally appended %zd\\n", pavolia_rc_pos);
            return ret;
        }
        pr_info("read_proxy: append pavolia %zu\\n", append_count);
        pavolia_rc_pos += append_count;
        ret += append_count;
        if (pavolia_rc_pos == (ssize_t)pavolia_rc_len) {
            pr_info("read_proxy: pavolia append done\\n");
        }
    }

    return ret;"""
content = content.replace(target4, replacement4)

# 3. Add append_pavolia_rc to read_iter_proxy
target5 = """            pr_info("read_iter_proxy: module append done\\n");
            free_module_rc();
        }
    }
    return ret;"""
replacement5 = """            pr_info("read_iter_proxy: module append done\\n");
            free_module_rc();
        }
    }

append_pavolia_rc:
    if (pavolia_rc_pos < pavolia_rc_len) {
        size_t append_count = copy_to_iter(pavolia_rc_buf + pavolia_rc_pos, pavolia_rc_len - pavolia_rc_pos, to);
        if (!append_count) {
            pr_info("read_iter_proxy: pavolia append error, appended %zd\\n", pavolia_rc_pos);
            return ret;
        }
        pr_info("read_iter_proxy: append pavolia %zu\\n", append_count);
        pavolia_rc_pos += append_count;
        ret += append_count;
        if (pavolia_rc_pos == (ssize_t)pavolia_rc_len) {
            pr_info("read_iter_proxy: pavolia append done\\n");
        }
    }
    return ret;"""
content = content.replace(target5, replacement5)

# 4. Add to ksu_sys_fstat
target6 = "size_t extra = ksu_rc_len + module_rc_len;"
replacement6 = "size_t extra = ksu_rc_len + module_rc_len + pavolia_rc_len;"
content = content.replace(target6, replacement6)

target7 = "pr_info(\"adding rc len: %ld -> %ld (static=%zu module=%zu)\", size, new_size, ksu_rc_len, module_rc_len);"
replacement7 = "pr_info(\"adding rc len: %ld -> %ld (static=%zu module=%zu pavolia=%zu)\", size, new_size, ksu_rc_len, module_rc_len, pavolia_rc_len);"
content = content.replace(target7, replacement7)

with open(filepath, "w") as f:
    f.write(content)
EOF

log "Pavolia Reine KernelSU integration applied successfully!"
