#!/usr/bin/env bash
workdir=$(pwd)

BUILD_START=$(date +%s)

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
VARIANT="KernelSU-Next"

# Download Clang
CLANG_DIR="$workdir/clang"
if [[ -z "$CLANG_BRANCH" ]]; then
  log "Downloading Clang..."
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
  log "Cloning Clang..."
  git clone --depth=1 -q "$CLANG_URL" -b "$CLANG_BRANCH" "$CLANG_DIR"
fi

export PATH="$CLANG_DIR/bin:$PATH"

# Extract clang version
COMPILER_STRING=$(clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')

# Clone GCC if not available
if ! ls $CLANG_DIR/bin | grep -q "aarch64-linux-gnu"; then
  log "Cloning GCC..."
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

if [[ "$ROOT_METHOD" == "Vanilla" ]]; then
  log "Skipping KernelSU integration (Vanilla Build)"
  VARIANT="Vanilla"
  
  # --- INJECT SELinux Rules for Vanilla (YamadaKSUCore) ---
  source "$workdir/selinux.sh"
  
  config --disable CONFIG_KSU
  config --enable CONFIG_YAMADA_KSU_CORE
  
  # Disable SUSFS configs for Vanilla
  config --disable CONFIG_KSU_SUSFS
  config --disable CONFIG_KSU_SUSFS_SUS_PATH
  config --disable CONFIG_KSU_SUSFS_SUS_MOUNT
  config --disable CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
  config --disable CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
  config --disable CONFIG_KSU_SUSFS_SUS_KSTAT
  config --disable CONFIG_KSU_SUSFS_SUS_OVERLAYFS
  config --disable CONFIG_KSU_SUSFS_TRY_UMOUNT
  config --disable CONFIG_KSU_SUSFS_SPOOF_UNAME
  config --disable CONFIG_KSU_SUSFS_ENABLE_LOG
  config --disable CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
  config --disable CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
  config --disable CONFIG_KSU_SUSFS_OPEN_REDIRECT
  config --disable CONFIG_KSU_SUSFS_SUS_MAP

  # Disable property spoofing configs for Vanilla
  config --disable CONFIG_PAVOLIA_REINE_RESETPROP
  config --disable CONFIG_AYUNDA_RISU_SAFEPROP
  config --disable CONFIG_YAMADA_DEV_IDENTIFICATION
else
  log "Setting KernelSU Next variant..."
  VARIANT="KernelSU-Next"
  install_ksu pershoot/KernelSU-Next "dev-susfs"

  # --- INJECT SELinux Rules ---
  # Rules are maintained in selinux.sh — edit that file to add new modules
  source "$workdir/selinux.sh"
  # ------------------------------------------

  # --- INJECT Pavolia Reine KernelSU Patch ---
  source "$workdir/PavoliaReinePatch.sh"
  # ------------------------------------------

  # --- INTEGRATE SUSFS ---
  source "$workdir/SUSFSPatch.sh"

  config --enable CONFIG_KSU
  config --disable CONFIG_KSU_MANUAL_SU
  config --enable CONFIG_KSU_SUSFS
fi

# ---
# NEW BRANDING SECTION
# ---
log "Finalizing build configuration with branding..."

# Determine branch type for the name
if [[ "$KERNEL_BRANCH" == "suikernel-experimental" ]]; then
    BRANCH_TAG="Experimental"
elif [[ "$KERNEL_BRANCH" == "suikernel-stable" ]]; then
    BRANCH_TAG="Stable"
else
    BRANCH_TAG="Dev" # Fallback if another branch is used
fi


# Setup initial branding
INTERNAL_BRAND_BASE="-${KERNEL_NAME}-${BRANCH_TAG}-${VARIANT}"

if [ -f "./common/build.config.gki" ]; then
    log "Patching build.config.gki for branding..."
    sed -i 's/check_defconfig//' ./common/build.config.gki
fi

config --disable CONFIG_LOCALVERSION_AUTO

# Declare needed variables
export KBUILD_BUILD_USER="$USER"
export KBUILD_BUILD_HOST="$HOST"
export KBUILD_BUILD_TIMESTAMP=$(date)
BUILD_FLAGS="-j$(nproc --all) ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out CROSS_COMPILE=$CROSS_COMPILE_PREFIX"
KERNEL_IMAGE="$KSRC/out/arch/arm64/boot/Image"
KMI_CHECK="$workdir/scripts/KMI_function_symbols_test.py"
MODULE_SYMVERS="$KSRC/out/Module.symvers"

touch .scmversion

# Extract SUSFS version
if [[ "$VARIANT" != "Vanilla" ]] && grep -q "SUSFS_VERSION" $KSRC/include/linux/susfs.h 2>/dev/null; then
    SUSFS_VERSION=$(grep -oP '#define SUSFS_VERSION "\K[^"]+' $KSRC/include/linux/susfs.h)
else
    SUSFS_VERSION="None"
fi

CLANG_VERSION=$(clang -v 2>&1 | head -n 1 | grep -oP 'clang version \K[0-9.]+')

text=$(
  cat << MSGEOF
*==== SuiKernel Builder ====*
*Linux Version*: $LINUX_VERSION
*Branch*: $BRANCH_TAG
*Runner*: $RUNNER_NAME
*Root Method*: $ROOT_METHOD | ${KSU_VERSION:-None}
*Clang*: $CLANG_VERSION
*Kakangku*: 100
MSGEOF
)

if [[ "$VARIANT" != "Vanilla" ]]; then
    text="$text
*SUSFS Version*: $SUSFS_VERSION"
fi

MESSAGE_ID=$(send_msg "$text" 2>&1 | jq -r .result.message_id)
echo "MESSAGE_ID=$MESSAGE_ID" >> $GITHUB_ENV

# Determine modes to build
if [[ "$PERMISSIVE_MODE" == "Both" ]]; then
    MODES=("Normal" "Permissive")
elif [[ "$PERMISSIVE_MODE" == "Permissive" ]]; then
    MODES=("Permissive")
else
    MODES=("Normal")
fi

# Clone AnyKernel once
cd $workdir
log "Cloning anykernel from $(simplify_gh_url "$ANYKERNEL_REPO")"
git clone -q --depth=1 $ANYKERNEL_REPO -b $ANYKERNEL_BRANCH anykernel_base
cd "$KSRC"

mkdir -p $workdir/artifacts

# Loop and build each mode
for MODE in "${MODES[@]}"; do
    log "================================================="
    log "   BUILDING MODE: $MODE"
    log "================================================="

    if [[ "$MODE" == "Permissive" ]]; then
        config --enable CONFIG_KANAGAWA_PERMISSIVE
        CURRENT_VARIANT="${VARIANT}-PERMISSIVE"
    else
        config --disable CONFIG_KANAGAWA_PERMISSIVE
        CURRENT_VARIANT="${VARIANT}"
    fi

    CURRENT_INTERNAL_BRAND="-${KERNEL_NAME}-${BRANCH_TAG}-${CURRENT_VARIANT}"
    CURRENT_KERNEL_RELEASE_NAME="${LINUX_VERSION}${CURRENT_INTERNAL_BRAND}"
    config --set-str CONFIG_LOCALVERSION "$CURRENT_INTERNAL_BRAND"
    
    log "Internal kernel version set to: ${CURRENT_KERNEL_RELEASE_NAME}"

    log "Generating config..."
    make $BUILD_FLAGS $KERNEL_DEFCONFIG

    log "Building kernel..."
    make $BUILD_FLAGS Image modules

    $KMI_CHECK "$KSRC/android/abi_gki_aarch64.xml" "$MODULE_SYMVERS"

    cd $workdir
    rm -rf anykernel
    cp -r anykernel_base anykernel
    
    if [[ $STATUS == "BETA" ]]; then
      BUILD_DATE=$(date -d "$KBUILD_BUILD_TIMESTAMP" +"%Y%m%d-%H%M")
      ZIP_NAME="${CURRENT_KERNEL_RELEASE_NAME}-${BUILD_DATE}.zip"
      sed -i "s/kernel.string=.*/kernel.string=${CURRENT_KERNEL_RELEASE_NAME} (${BUILD_DATE})/g" anykernel/anykernel.sh
    else
      ZIP_NAME="${CURRENT_KERNEL_RELEASE_NAME}.zip"
      sed -i "s/kernel.string=.*/kernel.string=${CURRENT_KERNEL_RELEASE_NAME}/g" anykernel/anykernel.sh
    fi

    cd anykernel
    log "Zipping anykernel ($MODE)..."
    cp $KERNEL_IMAGE .
    zip -r9 "$workdir/$ZIP_NAME" ./* >/dev/null
    cd $workdir

    BUILD_END=$(date +%s)
    BUILD_DIFF=$((BUILD_END - BUILD_START))
    BUILD_MINS=$((BUILD_DIFF / 60))
    BUILD_SECS=$((BUILD_DIFF % 60))
    BUILD_TIME_STR="${BUILD_MINS}m ${BUILD_SECS}s"

    CAPTION=$(cat << CAPEOF
Build Time: $BUILD_TIME_STR
Build By: $RUNNER_NAME
Variant: $CURRENT_VARIANT
Kakangku: 100
${MANAGER_VERSIONS}
CAPEOF
    )

    if [[ $STATUS == "BETA" ]]; then
      reply_file "$MESSAGE_ID" "$workdir/$ZIP_NAME" "$CAPTION"
    else
      mv "$workdir/$ZIP_NAME" "$workdir/artifacts/"
      reply_file "$MESSAGE_ID" "$workdir/artifacts/$ZIP_NAME" "$CAPTION"
    fi
    
    cd "$KSRC"
done

# Save metadata for Github Actions release job
if [[ $STATUS != "BETA" ]]; then
  echo "BASE_NAME=$KERNEL_NAME-$VARIANT" >> $GITHUB_ENV
  echo "BUILD_TIME=$BUILD_TIME_STR" >> $GITHUB_ENV
  (
    echo "LINUX_VERSION=$LINUX_VERSION"
    echo "KSU_VERSION=${KSU_VERSION:-Vanilla}"
    echo "ROOT_METHOD=$ROOT_METHOD"
    echo "KERNEL_NAME=$KERNEL_NAME"
    echo "RELEASE_REPO=$(simplify_gh_url "$GKI_RELEASES_REPO")"
    echo "COMPILER_STRING=$COMPILER_STRING"
    echo "SUSFS_VERSION=$SUSFS_VERSION"
    echo "CLANG_VERSION=$CLANG_VERSION"
    echo "MANAGER_VERSIONS_B64=$(echo "$MANAGER_VERSIONS" | base64 -w 0)"
  ) >> $workdir/artifacts/info.txt
fi

# --- FETCH KERNELSU-NEXT MANAGER APKS ---
if [[ "$VARIANT" == *"KernelSU-Next"* ]]; then
  log "Fetching latest KernelSU-Next Manager APKs from releases..."
  M_URL=$(curl -s -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/latest | jq -r '.assets[] | select(.name | contains("-spoofed") | not) | select(.name | endswith(".apk")) | .browser_download_url')
  S_URL=$(curl -s -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/latest | jq -r '.assets[] | select(.name | contains("-spoofed")) | select(.name | endswith(".apk")) | .browser_download_url')
  
  if [ -n "$M_URL" ] && [ "$M_URL" != "null" ]; then
    curl -sL "$M_URL" -o "$workdir/KernelSU-Next-Normal.apk"
    curl -sL "$S_URL" -o "$workdir/KernelSU-Next-Spoofed.apk"
    
    if [[ $STATUS == "BETA" ]]; then
      reply_file "$MESSAGE_ID" "$workdir/KernelSU-Next-Normal.apk" "KernelSU-Next Manager (Normal)"
      reply_file "$MESSAGE_ID" "$workdir/KernelSU-Next-Spoofed.apk" "KernelSU-Next Manager (Spoofed)"
    else
      mv "$workdir/KernelSU-Next-Normal.apk" "$workdir/artifacts/"
      mv "$workdir/KernelSU-Next-Spoofed.apk" "$workdir/artifacts/"
      reply_file "$MESSAGE_ID" "$workdir/artifacts/KernelSU-Next-Normal.apk" "KernelSU-Next Manager (Normal)"
      reply_file "$MESSAGE_ID" "$workdir/artifacts/KernelSU-Next-Spoofed.apk" "KernelSU-Next Manager (Spoofed)"
    fi
  else
    log "Failed to fetch Manager APKs from official releases API"
  fi
fi
