#!/bin/bash

# === Load environment variables ===
ENV_FILE="/opt/homelab_git/.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
fi

# === Configuration ===
SOURCE_DIR="/opt/docker"
TARGET_DIR="/opt/homelab_git"
LOG_FILE="/var/log/homelab_sync.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# === List of folder names to exclude (exact matches)
EXCLUDED_NAMES=(
  "data"
  "media"
  "export"
  "mnt"
  "pgdata"
  "redisdata"
  "mysql"
  "letsencrypt"
)

# === Logging Function ===
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOG_FILE"
}

log "🔄 Starting sync..."

cd "$TARGET_DIR" || { log "❌ Failed to enter $TARGET_DIR"; exit 1; }

CHANGED_FOLDERS=()


# === Webhook function ===
send_discord_message() {
    local content="$1"
    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "{\"content\": \"$content\"}" \
         "$DISCORD_WEBHOOK_URL" > /dev/null
}

# === Detect folders with changes, skipping excluded names ===
for folder in "$SOURCE_DIR"/*/; do
    folder_name=$(basename "$folder")

    # Skip if excluded
    if printf '%s\n' "${EXCLUDED_NAMES[@]}" | grep -qx "$folder_name"; then
        log "🚫 Skipping excluded folder: $folder_name"
        continue
    fi

    src="$SOURCE_DIR/$folder_name"
    dst="$TARGET_DIR/$folder_name"

    [ -d "$src" ] || continue

    if rsync -a --delete --dry-run "$src/" "$dst/" | grep -q .; then
        CHANGED_FOLDERS+=("$folder_name")
        log "🔁 Changes detected in: $folder_name"
    fi
done

if [ ${#CHANGED_FOLDERS[@]} -eq 0 ]; then
    log "✅ No changes to sync."
    exit 0
fi

# === Sync changed folders only ===
for folder_name in "${CHANGED_FOLDERS[@]}"; do
    log "➡️ Syncing: $folder_name"
    rsync -av --delete "$SOURCE_DIR/$folder_name/" "$TARGET_DIR/$folder_name/" \
      --exclude='data/' --exclude='media/' --exclude='export/' --exclude='mnt/' \
      --exclude='pgdata/' --exclude='redisdata/' --exclude='mysql/' --exclude='letsencrypt/' \
      | tee -a "$LOG_FILE"
done

# === Git logic ===
git pull
git add .

if git diff --cached --quiet; then
    log "⚠️ No staged changes to commit."
    exit 0
fi

# Notify Discord before commit prompt
send_discord_message "📝 [homelab_sync] Changes detected in: ${CHANGED_FOLDERS[*]}. Awaiting commit message..."

echo
read -rp "📝 Enter commit message: " commit_msg_
