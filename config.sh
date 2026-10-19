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
CLANG_URL="https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b"
CLANG_BRANCH="lineage-20.0"