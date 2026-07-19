#!/usr/bin/env bash
# YamadaIsAngryPatch.sh
# Expands Yamada's blocklist by checking Android properties using KernelSU-Next's init.rc injection

log "Applying YamadaIsAngry KernelSU blocklist patch..."

if [ ! -d "drivers/kernelsu" ]; then
    log "Error: drivers/kernelsu not found. KernelSU must be cloned before applying this patch."
    exit 1
fi

python3 - << 'EOF'
import sys
import os
import re

ksud_filepath = "drivers/kernelsu/runtime/ksud_integration.c"
c_filepath = "drivers/Yamada/yamada_is_angry.c"

if not os.path.exists(ksud_filepath):
    print(f"Error: {ksud_filepath} not found!", file=sys.stderr)
    sys.exit(1)

if not os.path.exists(c_filepath):
    print(f"Error: {c_filepath} not found! Make sure it exists in the kernel source.", file=sys.stderr)
    sys.exit(1)

# 1. Parse the C file for blocklisted devices
with open(c_filepath, "r") as f:
    c_code = f.read()

match = re.search(r'blocklisted_devices\[\]\s*=\s*\{([^}]*)\}', c_code, re.MULTILINE)
devices = []
if match:
    array_content = match.group(1)
    # Find all string literals (e.g. "X6882")
    devices = re.findall(r'"([^"]+)"', array_content)

if not devices:
    print("Warning: No devices found in blocklist array!")
else:
    print(f"Found blocklisted devices: {devices}")

# 2. Patch the KernelSU-Next file
with open(ksud_filepath, "r") as f:
    content = f.read()

target = '    "\\n";\n// clang-format on'

# Dynamically build the init.rc string
replacement = '    "\\n"\n'
for dev in devices:
    replacement += f'    "on property:ro.product.model=*\\n"\n'
    replacement += f'    "    exec u:r:su:s0 root root -- /system/bin/sh -c \\"getprop ro.product.model | grep -iq \'{dev}\' && echo c > /proc/sysrq-trigger\\"\\n"\n'
    replacement += f'    "\\n"\n'
    replacement += f'    "on property:ro.product.name=*\\n"\n'
    replacement += f'    "    exec u:r:su:s0 root root -- /system/bin/sh -c \\"getprop ro.product.name | grep -iq \'{dev}\' && echo c > /proc/sysrq-trigger\\"\\n"\n'
    replacement += f'    "\\n"\n'

replacement += '    "\\n";\n// clang-format on'

if target in content:
    content = content.replace(target, replacement)
    with open(ksud_filepath, "w") as f:
        f.write(content)
    print("Successfully injected dynamic Yamada property blocklist into ksud_integration.c")
else:
    print("Error: Could not find target KERNEL_SU_RC string in ksud_integration.c!", file=sys.stderr)
    sys.exit(1)
EOF

log "YamadaIsAngry property patch applied successfully!"
