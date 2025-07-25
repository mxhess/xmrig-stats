#!/bin/bash

# Configuration
TARGET_INTERVAL=30                    # Target share submission interval (seconds)
LOG_START_HOURS=8                     # Log period for hashrate calculation (hours)
SERVICE_NAME="xmrig-proxy"           # Service name
CONFIG_FILE="/path/to/xmrig-proxy/config.json"  # Path to config.json
LOG_FILE="/path/to/xmrig_proxy_diff.log"  # Log file for difficulty updates
MIN_DIFFICULTY=100000                # Minimum allowed difficulty
MAX_DIFFICULTY=5000000               # Maximum allowed difficulty

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
log_message "[-] Fetching XMRig proxy logs from the last $LOG_START_HOURS hours..."
journalctl -q -u "$SERVICE_NAME" --since "$LOG_START_HOURS hours ago" | grep -E "proxy.*kH/s|shares:.*\+[0-9]" > "$TEMP_FILE"

# Check if logs are empty
if [ ! -s "$TEMP_FILE" ]; then
    log_message "[-] Error: No relevant logs found for $SERVICE_NAME in the last $LOG_START_HOURS hours."
    echo "[-] Error: No logs found. Check service name or log availability."
    exit 1
fi

# Debug: Log first few lines of filtered logs
log_message "[-] Sample filtered logs:"
head -n 3 "$TEMP_FILE" | while read -r line; do
    log_message "[-] $line"
done

# Extract hashrates (in kH/s) from lines like "[timestamp] proxy X.XX kH/s, shares ..."
HASHRATES=$(grep "kH/s" "$TEMP_FILE" | grep -oE "[0-9]+\.[0-9]{2}\s+kH/s" | grep -oE "[0-9]+\.[0-9]{2}" | grep -v "^0\.00$")

# Check if hashrates were found
if [ -z "$HASHRATES" ]; then
    log_message "[-] Error: No valid hashrate data found in logs."
    echo "[-] Error: No valid hashrate data found."
    exit 1
fi

# Debug: Log extracted hashrates
log_message "[-] Extracted hashrates: $HASHRATES"

# Calculate average hashrate (convert kH/s to H/s)
HASH_COUNT=0
HASH_SUM=0
while read -r hashrate; do
    # Convert kH/s to H/s (multiply by 1000)
    HASH_SUM=$(echo "$HASH_SUM + ($hashrate * 1000)" | bc -l)
    HASH_COUNT=$((HASH_COUNT + 1))
done <<< "$HASHRATES"

if [ "$HASH_COUNT" -eq 0 ]; then
    log_message "[-] Error: No valid hashrates to process."
    echo "[-] Error: No valid hashrates to process."
    exit 1
fi

AVG_HASHRATE=$(echo "scale=2; $HASH_SUM / $HASH_COUNT" | bc -l)
log_message "[-] Average hashrate: $AVG_HASHRATE H/s"
echo "[+] Average hashrate: $AVG_HASHRATE H/s"

# Calculate optimal difficulty (Difficulty = Hashrate * Target Time)
OPTIMAL_DIFF=$(echo "scale=0; $AVG_HASHRATE * $TARGET_INTERVAL" | bc -l | cut -d. -f1)

# Validate difficulty
if [ "$OPTIMAL_DIFF" -lt "$MIN_DIFFICULTY" ]; then
    log_message "[-] Warning: Calculated difficulty ($OPTIMAL_DIFF) below minimum ($MIN_DIFFICULTY). Using minimum."
    OPTIMAL_DIFF=$MIN_DIFFICULTY
elif [ "$OPTIMAL_DIFF" -gt "$MAX_DIFFICULTY" ]; then
    log_message "[-] Warning: Calculated difficulty ($OPTIMAL_DIFF) above maximum ($MAX_DIFFICULTY). Using maximum."
    OPTIMAL_DIFF=$MAX_DIFFICULTY
fi

echo "[+] Recommended static difficulty for $TARGET_INTERVAL-second share submission: $OPTIMAL_DIFF"
log_message "[-] Recommended static difficulty: $OPTIMAL_DIFF"

# Count accepted shares from lines like "[timestamp] proxy X.XX kH/s, shares: X/0 +Y"
SHARE_COUNT=$(grep "shares:.*\+[0-9]" "$TEMP_FILE" | grep -oE "\+[0-9]+" | grep -oE "[0-9]+" | awk '{sum+=$1} END {print sum}')
if [ -z "$SHARE_COUNT" ] || [ "$SHARE_COUNT" -eq 0 ]; then
    echo "[-] Warning: No accepted shares found in logs. Difficulty estimate is based solely on hashrate."
    log_message "[-] Warning: No accepted shares found in logs."
else
    LOG_DURATION=$((LOG_START_HOURS * 3600)) # Convert hours to seconds
    SHARE_RATE=$(echo "scale=2; $LOG_DURATION / $SHARE_COUNT" | bc -l)
    echo "[+] Actual share submission rate: ~$SHARE_RATE seconds/share (based on $SHARE_COUNT shares)"
    log_message "[-] Actual share submission rate: ~$SHARE_RATE seconds/share (based on $SHARE_COUNT shares)"
fi

# Update XMRig-proxy config.json for enabled pools with existing separator
if [ -f "$CONFIG_FILE" ]; then
    # Check for enabled pools
    ENABLED_POOLS=$(jq '[.pools[] | select(.enabled == true)] | length' "$CONFIG_FILE")
    if [ "$ENABLED_POOLS" -eq 0 ]; then
        log_message "[-] Error: No enabled pools found in $CONFIG_FILE"
        echo "[-] Error: No enabled pools found in $CONFIG_FILE"
        exit 1
    fi

    # Backup config file
    BACKUP_FILE="${CONFIG_FILE}.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    log_message "[-] Backed up config to $BACKUP_FILE"

    # Track if any updates were made
    UPDATED=0

    # Update user field for each enabled pool
    ENABLED_POOL_INDICES=$(jq -r '.pools | to_entries | map(select(.value.enabled == true) | .key) | join(" ")' "$CONFIG_FILE")
    for i in $ENABLED_POOL_INDICES; do
        user_field=$(jq -r ".pools[$i].user" "$CONFIG_FILE")
        pool_url=$(jq -r ".pools[$i].url" "$CONFIG_FILE")
        log_message "[-] Parsing user field for pool $i ($pool_url): $user_field"
        # Check if user field contains a separator followed by a numeric difficulty
        if echo "$user_field" | grep -qE '[+._@][0-9]+$' && echo "$user_field" | grep -qE '[0-9]+$'; then
            # Extract wallet address (before separator), separator, and old difficulty
            wallet_address=$(echo "$user_field" | grep -oE "^[^+._@]+")
            separator=$(echo "$user_field" | grep -oE "[+._@]" | head -n 1)
            old_diff=$(echo "$user_field" | grep -oE "[0-9]+$")
            log_message "[-] Parsed: wallet=$wallet_address, separator=$separator, old_diff=$old_diff"
            # Replace old difficulty with new one
            new_user="${wallet_address}${separator}${OPTIMAL_DIFF}"
            # Escape new_user for jq
            escaped_new_user=$(printf '%s' "$new_user" | jq -R .)
            jq --arg index "$i" --argjson new_user "$escaped_new_user" '.pools[$index|tonumber].user = $new_user' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
            if [ $? -eq 0 ]; then
                mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                log_message "[-] Updated pool $i ($pool_url) user to $new_user"
                echo "[+] Updated pool $i ($pool_url) user to $new_user"
                UPDATED=1
            else
                log_message "[-] Error: Failed to update pool $i ($pool_url) user field"
                echo "[-] Error: Failed to update pool $i ($pool_url) user field"
            fi
        else
            # Suggest difficulty without guessing full format
            log_message "[-] Pool $i ($pool_url) has no numeric difficulty set. Suggested action: Append a static difficulty of $OPTIMAL_DIFF to your wallet address in the pool's required format (no changes made)"
            echo "[+] Pool $i ($pool_url) has no numeric difficulty set. Please append a static difficulty of $OPTIMAL_DIFF to your wallet address in the pool's required format"
        fi
    done

    # If no updates were made, log and notify
    if [ "$UPDATED" -eq 0 ]; then
        log_message "[-] No pools with numeric difficulty updated. Check user fields or set difficulty manually."
        echo "[+] No pools with numeric difficulty updated. Check user fields or set difficulty manually."
    else
        log_message "[-] Config updated, relying on XMRig-proxy auto-reload"
        echo "[+] Config updated, XMRig-proxy will auto-reload"
	rm "$BACKUP_FILE"
	log_message "[-] Removed backup config file $BACKUP_FILE"
    fi
else
    log_message "[-] Error: Config file $CONFIG_FILE not found"
    echo "[-] Error: Config file $CONFIG_FILE not found"
    exit 1
fi

