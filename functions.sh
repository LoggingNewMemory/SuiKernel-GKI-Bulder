#!/usr/bin/env bash

# ==============
#    Functions
# ==============

# Telegram functions
# upload_file <path/to/file>
upload_file() {
  local FILE="$1"
  if ! [[ -f $FILE ]]; then
    error "file $FILE doesn't exist"
  fi
  chmod 777 $FILE
  curl -s -F document=@"$FILE" "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
    -F "chat_id=$TG_CHAT_ID" \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=markdown"
}

# reply_file <message_id> <path/to/file>
reply_file() {
  local MESSAGE_ID="$1"
  local FILE="$2"
  if ! [[ -f $FILE ]]; then
    error "file $FILE doesn't exist"
  fi
  chmod 777 $FILE
  curl -s -F document=@"$FILE" "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" \
    -F "chat_id=$TG_CHAT_ID" \
    -F "reply_to_message_id=$MESSAGE_ID" \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=markdown"
}

# send_msg <text>
send_msg() {
  local MESSAGE="$1"
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=markdown" \
    -d "text=$MESSAGE"
}
# reply_msg <text>
reply_msg() {
  local MESSAGE_ID="$1"
  local MESSAGE="$2"
  curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TG_CHAT_ID" \
    -d "reply_to_message_id=$MESSAGE_ID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=markdown" \
    -d "text=$MESSAGE"
}

# KernelSU-related functions
install_ksu() {
  local REPO="$1"
  local REF="$2"
  local LATEST_TAG
  local URL

  if [[ -z "$REPO" ]]; then
    echo "Usage: install_ksu <user/repo> [ref]"
    exit 1
  fi

  # Set ref to latest tag if ref is zero
  LATEST_TAG=$(gh api "repos/$REPO/tags" --jq '.[0].name')
  if [[ -z "$REF" ]]; then
    REF="$LATEST_TAG"
  fi

  URL="https://raw.githubusercontent.com/$REPO/$REF/kernel/setup.sh"
  log "Installing KernelSU from $REPO | $REF"
  if ! curl -fLSs "$URL" -o ksu_setup.sh; then
    log "Failed to download from GitHub, trying jsdelivr..."
    curl -fLSs "https://cdn.jsdelivr.net/gh/$REPO@$REF/kernel/setup.sh" -o ksu_setup.sh
  fi
  bash ksu_setup.sh "$REF"
  rm -f ksu_setup.sh
  export KSU_VERSION="$LATEST_TAG"
}

# ksu_included() function
# Type: bool
ksu_included() {
  # if variant is not nksu then
  # kernelsu is included!
  [[ $VARIANT != "NKSU" ]]
  return $?
}

# susfs_included() function
# Type: bool
susfs_included() {
  [[ $KSU_SUSFS == "true" ]]
  return $?
}

# ksu_manual_hook() function
# Type: bool
ksu_manual_hook() {
  [[ $KSU_MANUAL_HOOK == "true" ]]
  return $?
}

# simplify_gh_url <github-repository-url>
simplify_gh_url() {
  local URL="$1"
  echo "$URL" | sed "s|https://github.com/||g" | sed "s|.git||g"
}

# Kernel scripts function
config() {
  $workdir/ksrc/scripts/config --file $DEFCONFIG_FILE $@
}

# Logging function
log() {
  echo -e "[LOG] $*"
}

error() {
  echo -e "[ERROR] $*"
  if [[ -n $MESSAGE_ID ]]; then
    reply_msg "$MESSAGE_ID" "❌ ERROR: $*"
    reply_file "$MESSAGE_ID" "$workdir/build.log"
  else
    send_msg "❌ ERROR: $*"
    upload_file "$workdir/build.log"
  fi
  exit 1
}
