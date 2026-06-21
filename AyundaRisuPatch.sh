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

filepath = "drivers/kernelsu/runtime/ksud_integration.c"

with open(filepath, "r") as f:
    content = f.read()

# Guard: skip if already patched
if "ayunda_exec_buf" in content:
    print("Ayunda Risu exec buffer already patched, skipping.")
    sys.exit(0)

# ---------------------------------------------------------------------------
# 1. Inject globals + ksu_ayunda_exec_once()
#
#    Inserts after EXPORT_SYMBOL(ksu_pavolia_add_prop) when Pavolia is
#    present, otherwise after the // clang-format on marker.
# ---------------------------------------------------------------------------
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
     *   on property:sys.boot_completed=1
     *       exec u:r:su:s0 root -- /system/bin/sh -c "<cmd>"
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

if "pavolia_rc_len = strlen" in content:
    anchor = "EXPORT_SYMBOL(ksu_pavolia_add_prop);\n"
    if anchor in content:
        content = content.replace(anchor, anchor + AYUNDA_GLOBALS, 1)
    else:
        anchor = "// clang-format on\n"
        content = content.replace(anchor, anchor + AYUNDA_GLOBALS, 1)
else:
    anchor = "// clang-format on\n"
    content = content.replace(anchor, anchor + AYUNDA_GLOBALS, 1)

# ---------------------------------------------------------------------------
# 2a. Extend the early-exit guard in read_proxy AND read_iter_proxy
#     (no count limit → replaces every occurrence, same as PavoliaReinePatch)
# ---------------------------------------------------------------------------
if "pavolia_rc_pos >= pavolia_rc_len) {" in content:
    content = content.replace(
        "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len) {",
        "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len && ayunda_exec_pos >= (ssize_t)ayunda_exec_len) {",
    )
else:
    content = content.replace(
        "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len) {",
        "if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && ayunda_exec_pos >= (ssize_t)ayunda_exec_len) {",
    )

# ---------------------------------------------------------------------------
# 2b. Add goto dispatch for ayunda in BOTH read_proxy and read_iter_proxy.
#     No count limit — mirrors how PavoliaReinePatch patches both functions.
# ---------------------------------------------------------------------------
if "goto append_pavolia_rc;" in content:
    content = content.replace(
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos < pavolia_rc_len)\n"
        "        goto append_pavolia_rc;",
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos < pavolia_rc_len)\n"
        "        goto append_pavolia_rc;\n"
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && pavolia_rc_pos >= pavolia_rc_len && ayunda_exec_pos < (ssize_t)ayunda_exec_len)\n"
        "        goto append_ayunda_exec;",
    )
else:
    content = content.replace(
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos < module_rc_len)\n"
        "        goto append_module_rc;",
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos < module_rc_len)\n"
        "        goto append_module_rc;\n"
        "    if (ksu_rc_pos >= ksu_rc_len && module_rc_pos >= module_rc_len && ayunda_exec_pos < (ssize_t)ayunda_exec_len)\n"
        "        goto append_ayunda_exec;",
    )

# ---------------------------------------------------------------------------
# 2c. Insert append_ayunda_exec label + block in read_proxy.
#
#     NOTE: pr_info strings in the C file contain \n (backslash + n, 2 chars).
#     In Python string literals that maps to \\n (one backslash escape + n).
# ---------------------------------------------------------------------------
AYUNDA_READ_PROXY_BLOCK = (
    "append_ayunda_exec:\n"
    "    if (ayunda_exec_pos < (ssize_t)ayunda_exec_len && (size_t)ret < count) {\n"
    "        size_t append_count = ayunda_exec_len - ayunda_exec_pos;\n"
    "        if (append_count > count - ret)\n"
    "            append_count = count - ret;\n"
    "        if (copy_to_user(buf + ret, ayunda_exec_buf + ayunda_exec_pos, append_count)) {\n"
    "            pr_info(\"read_proxy: ayunda append error, totally appended %zd\\n\", ayunda_exec_pos);\n"
    "            return ret;\n"
    "        }\n"
    "        pr_info(\"read_proxy: append ayunda %zu\\n\", append_count);\n"
    "        ayunda_exec_pos += append_count;\n"
    "        ret += append_count;\n"
    "        if (ayunda_exec_pos == (ssize_t)ayunda_exec_len) {\n"
    "            pr_info(\"read_proxy: ayunda append done\\n\");\n"
    "        }\n"
    "    }\n"
    "\n"
    "    return ret;"
)

if "append_pavolia_rc:" in content:
    # Insert our block in read_proxy, replacing its final `return ret;`
    # The marker is the closing brace of the pavolia block + blank line + return.
    target = (
        "        if (pavolia_rc_pos == (ssize_t)pavolia_rc_len) {\n"
        "            pr_info(\"read_proxy: pavolia append done\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        "    return ret;"
    )
    replacement = (
        "        if (pavolia_rc_pos == (ssize_t)pavolia_rc_len) {\n"
        "            pr_info(\"read_proxy: pavolia append done\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        + AYUNDA_READ_PROXY_BLOCK
    )
else:
    target = (
        "        if (module_rc_pos == (ssize_t)module_rc_len) {\n"
        "            pr_info(\"read_proxy: module append done\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "\n"
        "    return ret;"
    )
    replacement = (
        "        if (module_rc_pos == (ssize_t)module_rc_len) {\n"
        "            pr_info(\"read_proxy: module append done\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "\n"
        + AYUNDA_READ_PROXY_BLOCK
    )

if target in content:
    content = content.replace(target, replacement, 1)
else:
    print("ERROR: read_proxy pavolia/module tail not found — cannot insert append_ayunda_exec label!", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# 3. Insert append_ayunda_exec label + block in read_iter_proxy.
# ---------------------------------------------------------------------------
AYUNDA_READ_ITER_PROXY_BLOCK = (
    "append_ayunda_exec:\n"
    "    if (ayunda_exec_pos < (ssize_t)ayunda_exec_len) {\n"
    "        size_t append_count = copy_to_iter(ayunda_exec_buf + ayunda_exec_pos, ayunda_exec_len - ayunda_exec_pos, to);\n"
    "        if (!append_count) {\n"
    "            pr_info(\"read_iter_proxy: ayunda append error, appended %zd\\n\", ayunda_exec_pos);\n"
    "            return ret;\n"
    "        }\n"
    "        pr_info(\"read_iter_proxy: append ayunda %zu\\n\", append_count);\n"
    "        ayunda_exec_pos += append_count;\n"
    "        ret += append_count;\n"
    "        if (ayunda_exec_pos == (ssize_t)ayunda_exec_len) {\n"
    "            pr_info(\"read_iter_proxy: ayunda append done\\n\");\n"
    "        }\n"
    "    }\n"
    "    return ret;"
)

if "append_pavolia_rc:" in content:
    target_iter = (
        "            pr_info(\"read_iter_proxy: pavolia append done\\n\");\n"
        "        }\n"
        "    }\n"
        "    return ret;"
    )
    replacement_iter = (
        "            pr_info(\"read_iter_proxy: pavolia append done\\n\");\n"
        "        }\n"
        "    }\n"
        "\n"
        + AYUNDA_READ_ITER_PROXY_BLOCK
    )
else:
    target_iter = (
        "            pr_info(\"read_iter_proxy: module append done\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "    return ret;"
    )
    replacement_iter = (
        "            pr_info(\"read_iter_proxy: module append done\\n\");\n"
        "            free_module_rc();\n"
        "        }\n"
        "    }\n"
        "\n"
        + AYUNDA_READ_ITER_PROXY_BLOCK
    )

if target_iter in content:
    content = content.replace(target_iter, replacement_iter, 1)
else:
    print("ERROR: read_iter_proxy pavolia/module tail not found — cannot insert append_ayunda_exec label!", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# 4. Update ksu_sys_fstat to include ayunda_exec_len in reported file size
# ---------------------------------------------------------------------------
if "pavolia_rc_len" in content:
    content = content.replace(
        "size_t extra = ksu_rc_len + module_rc_len + pavolia_rc_len;",
        "size_t extra = ksu_rc_len + module_rc_len + pavolia_rc_len + ayunda_exec_len;",
    )
    content = content.replace(
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu pavolia=%zu)", size, new_size, ksu_rc_len, module_rc_len, pavolia_rc_len);',
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu pavolia=%zu ayunda=%zu)", size, new_size, ksu_rc_len, module_rc_len, pavolia_rc_len, ayunda_exec_len);',
    )
else:
    content = content.replace(
        "size_t extra = ksu_rc_len + module_rc_len;",
        "size_t extra = ksu_rc_len + module_rc_len + ayunda_exec_len;",
    )
    content = content.replace(
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu)", size, new_size, ksu_rc_len, module_rc_len);',
        'pr_info("adding rc len: %ld -> %ld (static=%zu module=%zu ayunda=%zu)", size, new_size, ksu_rc_len, module_rc_len, ayunda_exec_len);',
    )

with open(filepath, "w") as f:
    f.write(content)

print("Ayunda Risu exec buffer injected into ksud_integration.c successfully!")
AYUNDA_EOF

log "✅ Ayunda Risu KernelSU exec injection applied successfully!"
