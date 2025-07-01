#!/bin/bash

# === Load environment variables ===
ENV_FILE="/opt/docker/homelab/scripts/.env"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo "❌ .env file not found at $ENV_FILE"
    exit 1
fi

# === Configuration ===
SOURCE_DIR="/opt/docker/stacks"
TARGET_DIR="/opt/docker/homelab"
LOG_FILE="/var/log/homelab_sync.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# === Logging Function ===
log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOG_FILE"
}

log "🔄 Starting sync..."

cd "$TARGET_DIR" || { log "❌ Failed to enter $TARGET_DIR"; exit 1; }

# === Webhook function ===
send_discord_message() {
    local content="$1"
    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "{\"content\": \"$content\"}" \
         "$DISCORD_WEBHOOK_URL" > /dev/null
}



# === Sync ===
rsync -av --exclude-from='/opt/docker/homelab/scripts/exclude.txt' $SOURCE_DIR/ $TARGET_DIR/
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

git commit -m "$commit_msg_"
git push
