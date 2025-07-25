#!/bin/bash

# Configuration
TARGET_INTERVAL=30                    # Target share submission interval (seconds)
LOG_START_HOURS=8                    # Log period for hashrate calculation (hours)
SERVICE_NAME="xmrig-proxy"           # Systemd service name
CONFIG_FILE="/path/to/xmrig-proxy/config.json"  # Path to XMRig-proxy config.json
LOG_FILE="/var/log/xmrig_proxy_diff.log"  # Log file for difficulty updates
MIN_DIFFICULTY=100000                # Minimum allowed difficulty
MAX_DIFFICULTY=5000000               # Maximum allowed difficulty
DEFAULT_SEPARATOR='.'                # Default separator for suggested difficulty
RESTART_PROXY=0                      # 1 to restart xmrig-proxy, 0 to skip

# Temporary file for storing parsed logs
TEMP_FILE=$(mktemp)

# Function to clean up temporary file on exit
cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Fetch logs from journald for the specified time range
log_message "Fetching XMRig-proxy logs from the last $LOG_START_HOURS hours..."
journalctl -q -u "$SERVICE_NAME" --since "$LOG_START_HOURS hours ago" --no-pager | grep -E "proxy.*kH/s|accepted" > "$TEMP_FILE"

# Check if logs are empty
if [ ! -s "$TEMP_FILE" ]; then
    log_message "Error: No relevant logs found for $SERVICE_NAME in the last $LOG_START_HOURS hours."
    echo "Error: No relevant logs found. Check service name or log availability."
    exit 1
fi

# Extract hashrates (in kH/s) from lines like "[timestamp] proxy X.XX kH/s, shares: ..."
HASHRATES=$(grep "kH/s" "$TEMP_FILE" | grep -oP "\d+\.\d{2}\s+kH/s" | grep -oP "\d+\.\d{2}" | grep -v "^0\.00$")

# Check if hashrates were found
if [ -z "$HASHRATES" ]; then
    log_message "Error: No valid hashrate data found in logs."
    echo "Error: No valid hashrate data found."
    exit 1
fi

# Calculate average hashrate (convert kH/s to H/s)
HASH_COUNT=0
HASH_SUM=0
while read -r hashrate; do
    # Convert kH/s to H/s (multiply by 1000)
    HASH_SUM=$(echo "$HASH_SUM + ($hashrate * 1000)" | bc -l)
    HASH_COUNT=$((HASH_COUNT + 1))
done <<< "$HASHRATES"

if [ "$HASH_COUNT" -eq 0 ]; then
    log_message "Error: No valid hashrates to process."
    echo "Error: No valid hashrates to process."
    exit 1
fi

AVG_HASHRATE=$(echo "scale=2; $HASH_SUM / $HASH_COUNT" | bc -l)
log_message "Average hashrate: $AVG_HASHRATE H/s"

# Calculate optimal difficulty (Difficulty = Hashrate * Target Time)
OPTIMAL_DIFF=$(echo "scale=0; $AVG_HASHRATE * $TARGET_INTERVAL" | bc -l | cut -d. -f1)

# Validate difficulty
if [ "$OPTIMAL_DIFF" -lt "$MIN_DIFFICULTY" ]; then
    log_message "Warning: Calculated difficulty ($OPTIMAL_DIFF) below minimum ($MIN_DIFFICULTY). Using minimum."
    OPTIMAL_DIFF=$MIN_DIFFICULTY
elif [ "$OPTIMAL_DIFF" -gt "$MAX_DIFFICULTY" ]; then
    log_message "Warning: Calculated difficulty ($OPTIMAL_DIFF) above maximum ($MAX_DIFFICULTY). Using maximum."
    OPTIMAL_DIFF=$MAX_DIFFICULTY
fi

echo "Recommended static difficulty for $TARGET_INTERVAL-second share submission: $OPTIMAL_DIFF"
log_message "Recommended static difficulty: $OPTIMAL_DIFF"

# Count accepted shares to estimate actual share submission rate
SHARE_COUNT=$(grep -c "accepted" "$TEMP_FILE")
LOG_DURATION=$((LOG_START_HOURS * 3600)) # Convert hours to seconds
if [ "$SHARE_COUNT" -gt 0 ]; then
    SHARE_RATE=$(echo "scale=2; $LOG_DURATION / $SHARE_COUNT" | bc -l)
    echo "Actual share submission rate: ~$SHARE_RATE seconds/share (based on $SHARE_COUNT shares)"
    log_message "Actual share submission rate: ~$SHARE_RATE seconds/share (based on $SHARE_COUNT shares)"
else
    echo "Warning: No accepted shares found in logs. Difficulty estimate is based solely on hashrate."
    log_message "Warning: No accepted shares found in logs."
fi

# Update XMRig-proxy config.json for enabled pools with existing difficulty only
if [ -f "$CONFIG_FILE" ]; then
    # Check for enabled pools
    ENABLED_POOLS=$(jq '[.pools[] | select(.enabled == true)] | length' "$CONFIG_FILE")
    if [ "$ENABLED_POOLS" -eq 0 ]; then
        log_message "Error: No enabled pools found in $CONFIG_FILE"
        echo "Error: No enabled pools found in $CONFIG_FILE"
        exit 1
    fi

    # Backup config file
    BACKUP_FILE="${CONFIG_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    log_message "Backed up config to $BACKUP_FILE"

    # Track if any updates were made
    UPDATED=0

    # Update user field for each enabled pool with existing difficulty
    ENABLED_POOL_INDICES=$(jq -r '.pools | to_entries | map(select(.value.enabled == true) | .key) | join(" ")' "$CONFIG_FILE")
    for i in $ENABLED_POOL_INDICES; do
        user_field=$(jq -r ".pools[$i].user" "$CONFIG_FILE")
        pool_url=$(jq -r ".pools[$i].url" "$CONFIG_FILE")
        # Check if user field contains a difficulty (has separator followed by a number)
        if echo "$user_field" | grep -q '[+._]\d+$'; then
            # Extract wallet address and separator
            wallet_address=$(echo "$user_field" | grep -oP "^[^+._]+")
            separator=$(echo "$user_field" | grep -oP "[+._]")
            new_user="${wallet_address}${separator}${OPTIMAL_DIFF}"
            jq --arg index="$i" --arg new_user="$new_user" ".pools[\$index|tonumber].user = \$new_user" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
            mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
            log_message "Updated pool $i ($pool_url) user to $new_user"
            echo "Updated pool $i ($pool_url) user to $new_user"
            UPDATED=1
        else
            # Suggest difficulty for pools without one
            suggested_user="${user_field}${DEFAULT_SEPARATOR}${OPTIMAL_DIFF}"
            log_message "Pool $i ($pool_url) has no difficulty set. Suggested user: $suggested_user (no changes made)"
            echo "Pool $i ($pool_url) has no difficulty set. Please set user to: $suggested_user"
        fi
    done

    # If no updates were made, log and notify
    if [ "$UPDATED" -eq 0 ]; then
        log_message "No pools with existing difficulty updated. Check user fields or set difficulty manually."
        echo "No pools with existing difficulty updated. Check user fields or set difficulty manually."
    fi
else
    log_message "Error: Config file $CONFIG_FILE not found"
    echo "Error: Config file $CONFIG_FILE not found"
    exit 1
fi

# Restart XMRig-proxy if enabled and updates were made
if [ "$RESTART_PROXY" -eq 1 ] && [ "$UPDATED" -eq 1 ]; then
    log_message "Restarting XMRig-proxy service..."
    systemctl restart "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        log_message "XMRig-proxy restarted successfully"
        echo "XMRig-proxy restarted successfully"
    else
        log_message "Error: Failed to restart XMRig-proxy"
        echo "Error: Failed to restart XMRig-proxy"
        exit 1
    fi
fi

