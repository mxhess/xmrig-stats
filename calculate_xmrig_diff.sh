#!/bin/bash

# Set target share submission interval (in seconds)
TARGET_INTERVAL=30

# Time range for logs (in hours)
LOG_START_HOURS=72

# Service name for journald (adjust if your XMRig-proxy service name differs)
SERVICE_NAME="xmrig-proxy"

# Temporary file for storing parsed logs
TEMP_FILE=$(mktemp)

# Function to clean up temporary file on exit
cleanup() {
    rm -f "$TEMP_FILE"
}
trap cleanup EXIT

# Fetch logs from journald for the specified time range
echo "Fetching XMRig-proxy logs from the last $LOG_START_HOURS hours..."
journalctl -q -u "$SERVICE_NAME" --since "$LOG_START_HOURS hours ago" --no-pager | grep -E "proxy.*kH/s|accepted" > "$TEMP_FILE"

# Check if logs are empty
if [ ! -s "$TEMP_FILE" ]; then
    echo "Error: No relevant logs found for $SERVICE_NAME in the last $LOG_START_HOURS hours."
    exit 1
fi

# Extract hashrates (in kH/s) from lines like "[timestamp] proxy X.XX kH/s, shares: ..."
HASHRATES=$(grep "kH/s" "$TEMP_FILE" | grep -oP "\d+\.\d{2}\s+kH/s" | grep -oP "\d+\.\d{2}" | grep -v "^0\.00$")

# Check if hashrates were found
if [ -z "$HASHRATES" ]; then
    echo "Error: No valid hashrate data found in logs."
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
    echo "Error: No valid hashrates to process."
    exit 1
fi

AVG_HASHRATE=$(echo "scale=2; $HASH_SUM / $HASH_COUNT" | bc -l)
echo "Average hashrate: $AVG_HASHRATE H/s"

# Calculate optimal difficulty (Difficulty = Hashrate * Target Time)
OPTIMAL_DIFF=$(echo "scale=0; $AVG_HASHRATE * $TARGET_INTERVAL" | bc -l | cut -d. -f1)
echo "Recommended static difficulty for $TARGET_INTERVAL-second share submission: $OPTIMAL_DIFF"

# Count accepted shares to estimate actual share submission rate
SHARE_COUNT=$(grep -c "accepted" "$TEMP_FILE")
LOG_DURATION=$((LOG_START_HOURS * 3600)) # Convert hours to seconds
if [ "$SHARE_COUNT" -gt 0 ]; then
    SHARE_RATE=$(echo "scale=2; $LOG_DURATION / $SHARE_COUNT" | bc -l)
    echo "Actual share submission rate: ~$SHARE_RATE seconds/share (based on $SHARE_COUNT shares)"
else
    echo "Warning: No accepted shares found in logs. Difficulty estimate is based solely on hashrate."
fi

# Suggest adding to XMRig-proxy config
echo -e "\nTo set static difficulty, add to your XMRig-proxy config.json in the 'pool' section:"
echo -e "{\n  \"url\": \"your.pool.url:port\",\n  \"user\": \"your_wallet_address+$OPTIMAL_DIFF\",\n  ...\n}"

