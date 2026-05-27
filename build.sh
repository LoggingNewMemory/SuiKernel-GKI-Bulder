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

# --- INJECT SELinux Rules ---
log "Injecting Tenebrion SELinux rules..."
sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // Tenebrion — allow kernel to read screen state + write cpuset\n\
    ksu_allow(db, "kernel", "sysfs_leds", "dir", "search");\n\
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
    ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n' \
    drivers/kernelsu/selinux/rules.c

log "Injecting Anya Thermal SELinux rules..."
sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // Anya Thermal — allow kernel to write thermal zone mode\n\
    ksu_allow(db, "kernel", "sysfs_therm", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "read");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "write");\n\
    ksu_allow(db, "kernel", "sysfs_therm", "file", "open");\n' \
    drivers/kernelsu/selinux/rules.c

log "Injecting NTSYNC SELinux rules..."
sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // NTSYNC SEPol — Allow kernel background worker to auto-chmod and spoof as gpu_device\n\
    ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
    ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
    // NTSYNC SEPol — Explicitly allow Winlator to RW the spoofed device\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n' \
    drivers/kernelsu/selinux/rules.c

log "Injecting Ochinai Inaho Audio SELinux rules..."
sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    ksu_allow(db, "kernel", "kernel", "capability", "dac_override");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "search");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "write");\n\
    ksu_allow(db, "kernel", "cgroup", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "getattr");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "read");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "write");\n\
    ksu_allow(db, "kernel", "cgroup", "file", "open");\n' \
    drivers/kernelsu/selinux/rules.c

log "Injecting Schedutil Enforcer SELinux rules..."
sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // Schedutil Enforcer — allow kernel thread to write to CPU governor nodes\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "search");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "getattr");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "open");\n\
    ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "write");\n' \
    drivers/kernelsu/selinux/rules.c
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
    echo "COMPILER_STRING=$COMPILER_STRING"
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