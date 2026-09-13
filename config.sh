#!/usr/bin/env bash

# Kernel name
KERNEL_NAME="SuiKernel"
# Kernel Build variables
USER="KanagawaYamada"
HOST="HoshimachiSuisei"
TIMEZONE="Asia/Jakarta"
# AnyKernel
ANYKERNEL_REPO="https://github.com/LoggingNewMemory/SuiKernel-anykernel"
ANYKERNEL_BRANCH="gki"
# Kernel Source
KERNEL_REPO="https://github.com/LoggingNewMemory/SuiKernel-android12-5.10"
KERNEL_BRANCH="${KERNEL_BRANCH_ENV:-suikernel-stable}"
KERNEL_DEFCONFIG="gki_defconfig"
# Release repository
GKI_RELEASES_REPO="https://github.com/LoggingNewMemory/SuiKernel-Release"
# Clang
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/b669748458572622ed716407611633c5415da25c/clang-r416183b.tar.gz"
CLANG_BRANCH=""