#!/usr/bin/env bash
workdir=$(pwd)

# Handle error
set -e
exec > >(tee $workdir/build.log) 2>&1
trap 'error "Failed at line $LINENO [$BASH_COMMAND]"' ERR

# Import config and functions
source $workdir/config.sh
source $workdir/functions.sh

# Set timezone
export TZ="$TIMEZONE"

# Clone kernel source
KSRC="$workdir/ksrc"
log "Cloning kernel source from $(simplify_gh_url "$KERNEL_REPO")"
git clone -q --depth=1 $KERNEL_REPO -b $KERNEL_BRANCH $KSRC

cd $KSRC
LINUX_VERSION=$(make kernelversion)
DEFCONFIG_FILE=$(find ./arch/arm64/configs -name "$KERNEL_DEFCONFIG")
cd $workdir

# Set KernelSU Variant
log "Setting KernelSU variant..."
VARIANT="KSUN"

# Download Clang
CLANG_DIR="$workdir/clang"
if [[ -z "$CLANG_BRANCH" ]]; then
  log "🔽 Downloading Clang..."
  aria2c -q -c -x16 -s32 -k8M --file-allocation=falloc --timeout=60 --retry-wait=5 -o tarball "$CLANG_URL"
  mkdir -p "$CLANG_DIR"
  tar -xf tarball -C "$CLANG_DIR"
  rm tarball

  if [[ $(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l) -eq 1 ]] \
    && [[ $(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l) -eq 0 ]]; then
    SINGLE_DIR=$(find "$CLANG_DIR" -mindepth 1 -maxdepth 1 -type d)
    mv $SINGLE_DIR/* $CLANG_DIR/
    rm -rf $SINGLE_DIR
  fi
else
  log "🔽 Cloning Clang..."
  git clone --depth=1 -q "$CLANG_URL" -b "$CLANG_BRANCH" "$CLANG_DIR"
fi

export PATH="$CLANG_DIR/bin:$PATH"

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# Clone GCC if not available
if ! ls $CLANG_DIR/bin | grep -q "aarch64-linux-gnu"; then
  log "🔽 Cloning GCC..."
  git clone --depth=1 -q https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 $workdir/gcc
  export PATH="$workdir/gcc/bin:$PATH"
  CROSS_COMPILE_PREFIX="aarch64-linux-"
else
  CROSS_COMPILE_PREFIX="aarch64-linux-gnu-"
fi

cd $KSRC

## KernelSU setup
# Remove existing KernelSU drivers
for KSU_PATH in drivers/staging/kernelsu drivers/kernelsu KernelSU; do
  if [[ -d $KSU_PATH ]]; then
    log "KernelSU driver found in $KSU_PATH, Removing..."
    KSU_DIR=$(dirname "$KSU_PATH")

    [[ -f "$KSU_DIR/Kconfig" ]] && sed -i '/kernelsu/d' $KSU_DIR/Kconfig
    [[ -f "$KSU_DIR/Makefile" ]] && sed -i '/kernelsu/d' $KSU_DIR/Makefile

    rm -rf $KSU_PATH
  fi
done

# Install kernelsu (Next)
install_ksu pershoot/KernelSU-Next "dev-susfs"

# --- INTEGRATE SUSFS ---
log "Cloning and applying SUSFS patches..."
git clone --depth=1 -q https://gitlab.com/simonpunk/susfs4ksu -b gki-android12-5.10 "$workdir/susfs"
SUSFS_PATCHES="$workdir/susfs/kernel_patches"

cp -R "$SUSFS_PATCHES"/fs/* ./fs/
cp -R "$SUSFS_PATCHES"/include/* ./include/
patch -p1 < "$SUSFS_PATCHES"/50_add_susfs_in_gki-android12-5.10.patch
# -----------------------

# --- DYNAMICALLY INJECT TENEBRION & ANYA THERMAL RULES ---
log "Injecting Tenebrion and Anya Thermal SELinux rules into KernelSU..."
sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // Tenebrion — allow kernel to read screen state from sysfs\n\
    ksu_allow(db, "kernel", "sysfs_leds", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_leds", "file", "getattr");\n\
    \n\
    ksu_allow(db, "kernel", "sysfs_type", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_type", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_type", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_type", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_type", "file", "getattr");\n\
    \n\
    // Anya Thermal — allow kernel to write thermal zone mode\n\
    ksu_allow(db, "kernel", "sysfs_therm", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "write");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "open");\n' drivers/kernelsu/selinux/rules.c
# ------------------------------------------

# --- INJECT ZETAMIN (Built-in service script) ---
log "Injecting Zetamin display refresh rate script into KernelSU..."

# Create Zetamin script content
cat > /tmp/zetamin_inject.py << 'PYEOF'
import sys
import re

target_file = sys.argv[1]

with open(target_file, 'r') as f:
    content = f.read()

# The Zetamin script to embed
zetamin_script = r'''
const ZETAMIN_SCRIPT: &str = r#"#!/system/bin/sh
# Zetamin — Display refresh rate maximizer
# Author: Kanagawa Yamada

log -t zetamin "Zetamin starting..."

max_rate=$(cmd display dump 2>/dev/null | grep -Eo 'fps=[0-9.]+' | cut -f2 -d= | sort -nr | head -n1 | cut -d . -f 1)

if [ -n "$max_rate" ] && [ "$max_rate" -gt 60 ]; then
    settings put system min_refresh_rate "$max_rate"
    settings put system peak_refresh_rate "$max_rate"
    resetprop ro.surface_flinger.game_default_frame_rate_override "$max_rate"
    log -t zetamin "Display refresh rate locked to ${max_rate}Hz"
else
    log -t zetamin "Device does not support high refresh rate or detection failed (max_rate=${max_rate})"
fi

log -t zetamin "Zetamin done"
exit 0
"#;
'''

# Check if already injected
if 'ZETAMIN_SCRIPT' in content:
    print("Zetamin already injected, skipping.")
    sys.exit(0)

# Inject after the last `use` or `const INSTALLER_CONTENT` line in init_event.rs
inject_after = 'const INSTALLER_CONTENT'
# Actually inject into init_event.rs — find the on_boot_completed function

# Inject the const at top of file after the last import
import_end = content.rfind('\nuse ')
last_use_end = content.find('\n', import_end + 1)

new_content = content[:last_use_end + 1] + '\n' + zetamin_script + content[last_use_end + 1:]

# Now inject the execution call into on_boot_completed
boot_completed_hook = '''    // Zetamin — lock display refresh rate at boot
    {
        use std::io::Write;
        let zetamin_path = format!("{}/zetamin.sh", defs::WORKING_DIR);
        if let Ok(mut f) = std::fs::File::create(&zetamin_path) {
            let _ = f.write_all(ZETAMIN_SCRIPT.as_bytes());
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(&zetamin_path,
                    std::fs::Permissions::from_mode(0o755));
            }
            if let Err(e) = crate::module::exec_script(&zetamin_path, true) {
                warn!("Zetamin failed: {e}");
            }
        }
    }

'''

# Inject before run_stage("boot-completed", false)
new_content = new_content.replace(
    'run_stage("boot-completed", false);',
    boot_completed_hook + '    run_stage("boot-completed", false);'
)

with open(target_file, 'w') as f:
    f.write(new_content)

print("Zetamin injected successfully.")
PYEOF

# Find init_event.rs in KernelSU
INIT_EVENT_RS=$(find "$KSRC/drivers/kernelsu" -name "init_event.rs" 2>/dev/null | head -1)

# KernelSU Next userspace path
KSUD_INIT_EVENT="$KSRC/KernelSU-Next/userspace/ksud/src/init_event.rs"

# Try both locations
for RS_FILE in "$INIT_EVENT_RS" "$KSUD_INIT_EVENT"; do
    if [[ -f "$RS_FILE" ]]; then
        log "Found init_event.rs at $RS_FILE"
        python3 /tmp/zetamin_inject.py "$RS_FILE"
        log "✅ Zetamin injected into $RS_FILE"
        break
    fi
done
# ------------------------------------------

config --enable CONFIG_KSU
config --disable CONFIG_KSU_MANUAL_SU
config --enable CONFIG_KSU_SUSFS

# ---
# ✅ NEW BRANDING SECTION
# ---
log "🧹 Finalizing build configuration with branding..."

# Determine branch type for the name
if [[ "$KERNEL_BRANCH" == "suikernel-experimental" ]]; then
    BRANCH_TAG="Experimental"
elif [[ "$KERNEL_BRANCH" == "suikernel-stable" ]]; then
    BRANCH_TAG="Stable"
else
    BRANCH_TAG="Dev" # Fallback if another branch is used
fi

# This sets the string appended to the base kernel version for `uname -r`
# Format Example: -SuiKernel-Experimental-KSUN
INTERNAL_BRAND="-${KERNEL_NAME}-${BRANCH_TAG}-${VARIANT}"

# This defines the full user-facing name for zips and AnyKernel
# Format Example: 5.10.252-SuiKernel-Experimental-KSUN
export KERNEL_RELEASE_NAME="${LINUX_VERSION}${INTERNAL_BRAND}"

# Apply branding-specific modifications from your snippet
if [ -f "./common/build.config.gki" ]; then
    log "Patching build.config.gki for branding..."
    sed -i 's/check_defconfig//' ./common/build.config.gki
fi

# Set the kernel's local version for uname -r and disable auto-generation
config --set-str CONFIG_LOCALVERSION "$INTERNAL_BRAND"
config --disable CONFIG_LOCALVERSION_AUTO
log "✅ Internal kernel version set to: ${KERNEL_RELEASE_NAME}"


# Declare needed variables
export KBUILD_BUILD_USER="$USER"
export KBUILD_BUILD_HOST="$HOST"
export KBUILD_BUILD_TIMESTAMP=$(date)
BUILD_FLAGS="-j$(nproc --all) ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out CROSS_COMPILE=$CROSS_COMPILE_PREFIX"
KERNEL_IMAGE="$KSRC/out/arch/arm64/boot/Image"
KMI_CHECK="$workdir/scripts/KMI_function_symbols_test.py"
MODULE_SYMVERS="$KSRC/out/Module.symvers"

# --- ADD THIS LINE ---
# Stop the kernel from appending the '+' for uncommitted changes
touch .scmversion
# ---------------------

text=$(
  cat << EOF
*==== SuiKernel Builder ====*
🐧 *Linux Version*: $LINUX_VERSION
🐱 *Branch*: $BRANCH_TAG
📅 *Build Date*: $KBUILD_BUILD_TIMESTAMP
📛 *KernelSU*: ${KSU} | $KSU_VERSION
🔰 *Compiler*: $COMPILER_STRING
😸 *Kakangkuh*: 100
EOF
)
MESSAGE_ID=$(send_msg "$text" 2>&1 | jq -r .result.message_id)

# --- SAVE MSG ID FOR GITHUB WORKFLOW ---
echo "MESSAGE_ID=$MESSAGE_ID" >> $GITHUB_ENV
# ---------------------------------------

## Build GKI
log "Generating config..."
make $BUILD_FLAGS $KERNEL_DEFCONFIG

# Upload defconfig if we are doing defconfig
if [[ $TODO == "defconfig" ]]; then
  log "Uploading defconfig..."
  upload_file $KSRC/out/.config
  exit 0
fi

# Build the actual kernel
log "Building kernel..."
make $BUILD_FLAGS Image modules

# Check KMI Function symbol
$KMI_CHECK "$KSRC/android/abi_gki_aarch64.xml" "$MODULE_SYMVERS"

## Post-compiling stuff
cd $workdir

# Clone AnyKernel
log "Cloning anykernel from $(simplify_gh_url "$ANYKERNEL_REPO")"
git clone -q --depth=1 $ANYKERNEL_REPO -b $ANYKERNEL_BRANCH anykernel

# Set kernel string in anykernel
if [[ $STATUS == "BETA" ]]; then
  BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%Y%m%d-%H%M")
  # Appends the date to the BETA zip
  ZIP_NAME="${KERNEL_RELEASE_NAME}-${BUILD_DATE}.zip"
  sed -i \
    "s/kernel.string=.*/kernel.string=${KERNEL_RELEASE_NAME} (${BUILD_DATE})/g" \
    $workdir/anykernel/anykernel.sh
else
  # Clean name for Stable/Release zips
  ZIP_NAME="${KERNEL_RELEASE_NAME}.zip"
  sed -i \
    "s/kernel.string=.*/kernel.string=${KERNEL_RELEASE_NAME}/g" \
    $workdir/anykernel/anykernel.sh
fi

# Zip the anykernel
cd anykernel
log "Zipping anykernel..."
cp $KERNEL_IMAGE .
zip -r9 $workdir/$ZIP_NAME ./*
cd -

if [[ $STATUS != "BETA" ]]; then
  echo "BASE_NAME=$KERNEL_NAME-$VARIANT" >> $GITHUB_ENV
  mkdir -p $workdir/artifacts
  # Only move zips
  mv $workdir/*.zip $workdir/artifacts
fi

if [[ $LAST_BUILD == "true" && $STATUS != "BETA" ]]; then
  (
    echo "LINUX_VERSION=$LINUX_VERSION"
    echo "KSU_NEXT_VERSION=$(gh api repos/KernelSU-Next/KernelSU-Next/tags --jq '.[0].name')"
    echo "KERNEL_NAME=$KERNEL_NAME"
    echo "RELEASE_REPO=$(simplify_gh_url "$GKI_RELEASES_REPO")"
  ) >> $workdir/artifacts/info.txt
fi

if [[ $STATUS == "BETA" ]]; then
  reply_file "$MESSAGE_ID" "$workdir/$ZIP_NAME"
else
  log "✅ Build Succeeded. Artifact link will be sent by GitHub Action."
fi

# Always send the build log on success, regardless of status
reply_file "$MESSAGE_ID" "$workdir/build.log"

exit 0
