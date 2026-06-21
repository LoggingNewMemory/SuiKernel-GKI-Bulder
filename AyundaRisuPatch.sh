#!/usr/bin/env bash
# AyundaRisuPatch.sh
# Applies the Ayunda Risu Native Root Exec integration to KernelSU.
# Injects ksu_ayunda_exec_once() and its RC-stream buffer into
# drivers/kernelsu/runtime/ksud_integration.c so that kernel drivers can
# queue shell commands that execute as  exec u:r:su:s0 root  at boot.
# Sourced by build.sh — must be called from inside $KSRC, after
# PavoliaReinePatch.sh (so the Pavolia buffer anchor is already in place).
# Author: Kanagawa Yamada

log "Applying Ayunda Risu KernelSU exec integration..."

if [ ! -f "drivers/kernelsu/runtime/ksud_integration.c" ]; then
    log "Warning: ksud_integration.c not found, skipping Ayunda Risu exec patch."
    return 0
fi

python3 - << 'AYUNDA_EOF'
import sys
import os

filepath = "drivers/kernelsu/runtime/ksud_integration.c"

with open(filepath, "r") as f:
    content = f.read()

# Guard: skip if already patched
if "ayunda_exec_buf" in content:
    print("Ayunda Risu exec buffer already patched, skipping.")
    sys.exit(0)

# 1. Add the Ayunda exec buffer globals and ksu_ayunda_exec_once() after
#    the pavolia_rc_len definition (which PavoliaReinePatch already added),
#    or after the clang-format on marker if running standalone.
#
#    ksu_ayunda_exec_once() appends a boot_completed init.rc action that
#    invokes /system/bin/sh -c "<cmd>" under u:r:su:s0 root.
#    Each call is limited to AYUNDA_MAX_CMD bytes; the total buffer is
#    AYUNDA_BUF_SIZE bytes. Commands exceeding the budget are dropped with
#    a pr_warn (never silently "succeed").
#
# We insert after the pavolia block when present; otherwise after // clang-format on.

AYUNDA_GLOBALS = """
/* -----------------------------------------------------------------------
 * Ayunda Risu Native Root Exec — init.rc command queue
 * Queued commands are appended to the init.rc stream injected by KernelSU
 * and execute as:  exec u:r:su:s0 root -- /system/bin/sh -c "<cmd>"
 * This is deliberately boot-time only. Post-boot execution must go through
 * the ksud userspace daemon or a kernel workqueue with a privileged cred.
 * ----------------------------------------------------------------------- */
#define AYUNDA_BUF_SIZE  8192
#define AYUNDA_MAX_CMD   512
char ayunda_exec_buf[AYUNDA_BUF_SIZE] = {0};
size_t ayunda_exec_len = 0;
ssize_t ayunda_exec_pos = 0;

void ksu_ayunda_exec_once(const char *cmd) {
    char entry[AYUNDA_MAX_CMD + 128];
    int written;
    if (!cmd || !*cmd) {
        pr_warn("ayunda_risu: empty command, ignoring\\n");
        return;
    }
    /*
     * Build an init.rc stanza that runs on boot_completed so /data and
     * /system are fully mounted and the KernelSU domain is active.
     *
     * Format:
     *   on property:sys.boot_completed=1\n
     *       exec u:r:su:s0 root -- /system/bin/sh -c "<cmd>"\n
     */
    written = snprintf(entry, sizeof(entry),
        "\\non property:sys.boot_completed=1\\n"
        "    exec u:r:su:s0 root -- /system/bin/sh -c \\"%s\\"\\n",
        cmd);
    if (written <= 0 || (size_t)written >= sizeof(entry)) {
        pr_warn("ayunda_risu: command too long or format error, dropping\\n");
        return;
    }
    if (ayunda_exec_len + (size_t)written >= AYUNDA_BUF_SIZE) {
        pr_warn("ayunda_risu: exec buffer full, dropping command: %s\\n", cmd);
        return;
    }
    strlcat(ayunda_exec_buf, entry, sizeof(ayunda_exec_buf));
    ayunda_exec_len = strlen(ayunda_exec_buf);
    pr_info("ayunda_risu: queued for init.rc exec: %s\\n", cmd);
}
EXPORT_SYMBOL(ksu_ayunda_exec_once);
"""

# Prefer inserting after the Pavolia block (if already patched)
if "pavolia_rc_len = strlen" in content:
    target = "EXPORT_SYMBOL(ksu_pavolia_add_prop);\n"
    if target in content:
        content = content.replace(target, target + AYUNDA_GLOBALS)
    else:
        # Fallback: insert after // clang-format on
        target = "// clang-format on\n"
        content = content.replace(target, target + AYUNDA_GLOBALS, 1)
else:
    target = "// clang-format on\n"
    content = content.replace(target, target + AYUNDA_GLOBALS, 1)

# 2. Wire ayunda_exec_buf into read_proxy — append after module_rc block.
#    Mirror the pavolia pattern exactly.

# 2a. Extend the early-exit check in read_proxy
target_early_exit = "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len) {"
replacement_early_exit = "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len && ayunda_exec_pos >= (ssize_t)ayunda_exec_len) {"

if target_early_exit in content:
    content = content.replace(target_early_exit, replacement_early_exit)
else:
    # Pavolia patch not present; extend the two-buffer version
    target_early_exit2 = "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len) {"
    replacement_early_exit2 = "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && ayunda_exec_pos >= (ssize_t)ayunda_exec_len) {"
    content = content.replace(target_early_exit2, replacement_early_exit2)

# 2b. Add goto for ayunda after pavolia (or after module if pavolia absent)
if "goto append_pavolia_rc;" in content:
    target_goto = (
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos < pavolia_rc_len)\n"
        "        goto append_pavolia_rc;"
    )
    replacement_goto = target_goto + (
        "\n    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len && ayunda_exec_pos < (ssize_t)ayunda_exec_len)\n"
        "        goto append_ayunda_exec;"
    )
    content = content.replace(target_goto, replacement_goto, 1)
else:
    # No pavolia: insert after the module_rc goto
    target_goto2 = (
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos < module_rc_len)\n"
        "        goto append_module_rc;"
    )
    replacement_goto2 = target_goto2 + (
        "\n    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && ayunda_exec_pos < (ssize_t)ayunda_exec_len)\n"
        "        goto append_ayunda_exec;"
    )
    content = content.replace(target_goto2, replacement_goto2, 1)

# 2c. Insert the append_ayunda_exec block before the final `return ret;` in read_proxy
if "append_pavolia_rc:" in content:
    target_return = (
        "        if (pavolia_rc_pos == (ssize_t)pavolia_rc_len) {\n"
        "            pr_info(\"read_proxy: pavolia append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        "    return ret;"
    )
    replacement_return = (
        "        if (pavolia_rc_pos == (ssize_t)pavolia_rc_len) {\n"
        "            pr_info(\"read_proxy: pavolia append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        "append_ayunda_exec:\n"
        "    if (ayunda_exec_pos < (ssize_t)ayunda_exec_len && (size_t)ret < count) {\n"
        "        size_t append_count = ayunda_exec_len - ayunda_exec_pos;\n"
        "        if (append_count > count - ret)\n"
        "            append_count = count - ret;\n"
        "        if (copy_to_user(buf + ret, ayunda_exec_buf + ayunda_exec_pos, append_count)) {\n"
        "            pr_info(\"read_proxy: ayunda append error, totally appended %zd\\\\n\", ayunda_exec_pos);\n"
        "            return ret;\n"
        "        }\n"
        "        pr_info(\"read_proxy: append ayunda %zu\\\\n\", append_count);\n"
        "        ayunda_exec_pos += append_count;\n"
        "        ret += append_count;\n"
        "        if (ayunda_exec_pos == (ssize_t)ayunda_exec_len) {\n"
        "            pr_info(\"read_proxy: ayunda append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        "    return ret;"
    )
    content = content.replace(target_return, replacement_return, 1)
else:
    target_return2 = (
        "        if (module_rc_pos == (ssize_t)module_rc_len) {\n"
        "            pr_info(\"read_proxy: module append done\\\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "\n"
        "    return ret;"
    )
    replacement_return2 = (
        "        if (module_rc_pos == (ssize_t)module_rc_len) {\n"
        "            pr_info(\"read_proxy: module append done\\\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "\n"
        "append_ayunda_exec:\n"
        "    if (ayunda_exec_pos < (ssize_t)ayunda_exec_len && (size_t)ret < count) {\n"
        "        size_t append_count = ayunda_exec_len - ayunda_exec_pos;\n"
        "        if (append_count > count - ret)\n"
        "            append_count = count - ret;\n"
        "        if (copy_to_user(buf + ret, ayunda_exec_buf + ayunda_exec_pos, append_count)) {\n"
        "            pr_info(\"read_proxy: ayunda append error, totally appended %zd\\\\n\", ayunda_exec_pos);\n"
        "            return ret;\n"
        "        }\n"
        "        pr_info(\"read_proxy: append ayunda %zu\\\\n\", append_count);\n"
        "        ayunda_exec_pos += append_count;\n"
        "        ret += append_count;\n"
        "        if (ayunda_exec_pos == (ssize_t)ayunda_exec_len) {\n"
        "            pr_info(\"read_proxy: ayunda append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        "    return ret;"
    )
    content = content.replace(target_return2, replacement_return2, 1)

# 3. Wire ayunda_exec_buf into read_iter_proxy — same pattern
if "append_pavolia_rc:" in content:
    target_iter_goto = (
        "            pr_info(\"read_iter_proxy: pavolia append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "    return ret;"
    )
    replacement_iter_goto = (
        "            pr_info(\"read_iter_proxy: pavolia append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        "append_ayunda_exec:\n"
        "    if (ayunda_exec_pos < (ssize_t)ayunda_exec_len) {\n"
        "        size_t append_count = copy_to_iter(ayunda_exec_buf + ayunda_exec_pos, ayunda_exec_len - ayunda_exec_pos, to);\n"
        "        if (!append_count) {\n"
        "            pr_info(\"read_iter_proxy: ayunda append error, appended %zd\\\\n\", ayunda_exec_pos);\n"
        "            return ret;\n"
        "        }\n"
        "        pr_info(\"read_iter_proxy: append ayunda %zu\\\\n\", append_count);\n"
        "        ayunda_exec_pos += append_count;\n"
        "        ret += append_count;\n"
        "        if (ayunda_exec_pos == (ssize_t)ayunda_exec_len) {\n"
        "            pr_info(\"read_iter_proxy: ayunda append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "    return ret;"
    )
    content = content.replace(target_iter_goto, replacement_iter_goto, 1)
else:
    target_iter_goto2 = (
        "            pr_info(\"read_iter_proxy: module append done\\\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "    return ret;"
    )
    replacement_iter_goto2 = (
        "            pr_info(\"read_iter_proxy: module append done\\\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "\n"
        "append_ayunda_exec:\n"
        "    if (ayunda_exec_pos < (ssize_t)ayunda_exec_len) {\n"
        "        size_t append_count = copy_to_iter(ayunda_exec_buf + ayunda_exec_pos, ayunda_exec_len - ayunda_exec_pos, to);\n"
        "        if (!append_count) {\n"
        "            pr_info(\"read_iter_proxy: ayunda append error, appended %zd\\\\n\", ayunda_exec_pos);\n"
        "            return ret;\n"
        "        }\n"
        "        pr_info(\"read_iter_proxy: append ayunda %zu\\\\n\", append_count);\n"
        "        ayunda_exec_pos += append_count;\n"
        "        ret += append_count;\n"
        "        if (ayunda_exec_pos == (ssize_t)ayunda_exec_len) {\n"
        "            pr_info(\"read_iter_proxy: ayunda append done\\\\n\");\n"
        "        }\n"
        "    }\n"
        "    return ret;"
    )
    content = content.replace(target_iter_goto2, replacement_iter_goto2, 1)

# 4. Update ksu_sys_fstat to include ayunda_exec_len in the reported file size
if "pavolia_rc_len" in content:
    target_extra = "size_t extra = ksu_rc_len + module_rc_len + pavolia_rc_len;"
    replacement_extra = "size_t extra = ksu_rc_len + module_rc_len + pavolia_rc_len + ayunda_exec_len;"
    target_pr = (
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu pavolia=%zu)",'
        ' size, new_size, ksu_rc_len, module_rc_len, pavolia_rc_len);'
    )
    replacement_pr = (
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu pavolia=%zu ayunda=%zu)",'
        ' size, new_size, ksu_rc_len, module_rc_len, pavolia_rc_len, ayunda_exec_len);'
    )
else:
    target_extra = "size_t extra = ksu_rc_len + module_rc_len;"
    replacement_extra = "size_t extra = ksu_rc_len + module_rc_len + ayunda_exec_len;"
    target_pr = (
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu)",'
        ' size, new_size, ksu_rc_len, module_rc_len);'
    )
    replacement_pr = (
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu ayunda=%zu)",'
        ' size, new_size, ksu_rc_len, module_rc_len, ayunda_exec_len);'
    )
content = content.replace(target_extra, replacement_extra)
content = content.replace(target_pr, replacement_pr)

with open(filepath, "w") as f:
    f.write(content)

print("Ayunda Risu exec buffer injected into ksud_integration.c successfully!")
AYUNDA_EOF

log "✅ Ayunda Risu KernelSU exec injection applied successfully!"
