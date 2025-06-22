#!/bin/bash

# Check if a pool URL argument is provided
if [ -z "$1" ]; then
    echo "Error: Please provide a pool URL as an argument."
    echo "Usage: $0 <pool_url>"
    exit 1
fi

echo -n "Run time: "
date "+%Y-%m-%d %H:%M%P"

# Define the config file path
CONFIG_FILE="xmrig-proxy/config.json"
TEMP_FILE="xmrig-proxy/config_temp.json"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq to proceed."
    exit 1
fi

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file $CONFIG_FILE not found."
    exit 1
fi

# Validate if the provided pool URL exists in the config
POOL_EXISTS=$(jq --arg url "$1" '.pools[] | select(.url == $url)' "$CONFIG_FILE")
if [ -z "$POOL_EXISTS" ]; then
    echo "Error: Pool URL $1 not found in $CONFIG_FILE."
    exit 1
fi

# Create a temporary file with updated pool settings
jq --arg url "$1" '
  .pools = [.pools[] | if .url == $url then . + {"enabled": true} else . + {"enabled": false} end]
' "$CONFIG_FILE" > "$TEMP_FILE"

# Check if jq command was successful
if [ $? -ne 0 ]; then
    echo "Error: Failed to process JSON with jq."
    rm -f "$TEMP_FILE"
    exit 1
fi

# Move the temporary file to replace the original config file
mv "$TEMP_FILE" "$CONFIG_FILE"

# Verify the update
echo "Pool $1 has been enabled. All other pools disabled."
jq '.pools[] | {url: .url, enabled: .enabled}' "$CONFIG_FILE"

exit 0

