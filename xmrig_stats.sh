#!/bin/bash

# Configuration
PROXY_HOST="127.0.0.1"
PROXY_PORT="8080"
ACCESS_TOKEN=""
REDIS_HOST="localhost"
REDIS_PORT="6379"
UPDATE_INTERVAL=5
DATA_TTL=$((3*60*60))  # 3 hours in seconds

# Redis keys
SUMMARY_KEY="xmrig:summary"
WORKERS_KEY="xmrig:workers"
MINERS_KEY="xmrig:miners"
HASHRATE_HISTORY_KEY="xmrig:hashrate_history"

# Ensure required tools are installed
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Aborting."; exit 1; }
command -v redis-cli >/dev/null 2>&1 || { echo >&2 "redis-cli is required but not installed. Aborting."; exit 1; }

# Function to fetch and store stats
fetch_and_store_stats() {
    local timestamp=$(date +%s)
    local headers=""
    [ -n "$ACCESS_TOKEN" ] && headers="-H 'Authorization: Bearer $ACCESS_TOKEN'"

    # Fetch summary data
    summary=$(curl -s $headers "http://${PROXY_HOST}:${PROXY_PORT}/1/summary")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch summary data"
        return 1
    fi

    # Store summary data in Redis
    echo "$summary" | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -x SET "$SUMMARY_KEY" EX "$DATA_TTL" >/dev/null

    # Extract and store hashrate
    hashrate=$(echo "$summary" | jq -r '.hashrate.total[0] // 0')
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ZADD "$HASHRATE_HISTORY_KEY" "$timestamp" "$hashrate" >/dev/null
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EXPIRE "$HASHRATE_HISTORY_KEY" "$DATA_TTL" >/dev/null

    # Clean up old hashrate data
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ZREMRANGEBYSCORE "$HASHRATE_HISTORY_KEY" 0 $((timestamp - DATA_TTL)) >/dev/null

    # Fetch workers data
    workers=$(curl -s $headers "http://${PROXY_HOST}:${PROXY_PORT}/1/workers")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch workers data"
        return 1
    fi
    echo "$workers" | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -x SET "$WORKERS_KEY" EX "$DATA_TTL" >/dev/null

    # Fetch miners data
    miners=$(curl -s $headers "http://${PROXY_HOST}:${PROXY_PORT}/1/miners")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch miners data"
        return 1
    fi
    echo "$miners" | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -x SET "$MINERS_KEY" EX "$DATA_TTL" >/dev/null

    echo "Stats updated at $(date)"
}

# Function to display current stats
display_stats() {
    # Retrieve data from Redis
    summary=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$SUMMARY_KEY")
    workers=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$WORKERS_KEY")
    miners=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT葬

System: I'll help convert the XMRig Proxy stats webpage into a shell script that fetches stats locally and stores them in a Redis instance. Here's the implementation that meets your requirements:

<xaiArtifact artifact_id="35cff0df-8e79-4b06-98f1-c83d7bf6d195" artifact_version_id="e90c42b2-89ad-4772-bba7-b62bae83a16c" title="xmrig_stats.sh" contentType="text/x-shellscript">
#!/bin/bash

# Configuration
PROXY_HOST="127.0.0.1"
PROXY_PORT="8080"
ACCESS_TOKEN=""
REDIS_HOST="localhost"
REDIS_PORT="6379"
UPDATE_INTERVAL=5
DATA_TTL=$((3*60*60))  # 3 hours in seconds

# Redis keys
SUMMARY_KEY="xmrig:summary"
WORKERS_KEY="xmrig:workers"
MINERS_KEY="xmrig:miners"
HASHRATE_HISTORY_KEY="xmrig:hashrate_history"

# Ensure required tools are installed
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required but not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required but not installed. Aborting."; exit 1; }
command -v redis-cli >/dev/null 2>&1 || { echo >&2 "redis-cli is required but not installed. Aborting."; exit 1; }

# Function to fetch and store stats
fetch_and_store_stats() {
    local timestamp=$(date +%s)
    local headers=""
    [ -n "$ACCESS_TOKEN" ] && headers="-H 'Authorization: Bearer $ACCESS_TOKEN'"

    # Fetch summary data
    summary=$(curl -s $headers "http://${PROXY_HOST}:${PROXY_PORT}/1/summary")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch summary data"
        return 1
    fi

    # Store summary data in Redis
    echo "$summary" | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -x SET "$SUMMARY_KEY" EX "$DATA_TTL" >/dev/null

    # Extract and store hashrate
    hashrate=$(echo "$summary" | jq -r '.hashrate.total[0] // 0')
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ZADD "$HASHRATE_HISTORY_KEY" "$timestamp" "$hashrate" >/dev/null
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EXPIRE "$HASHRATE_HISTORY_KEY" "$DATA_TTL" >/dev/null

    # Clean up old hashrate data
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ZREMRANGEBYSCORE "$HASHRATE_HISTORY_KEY" 0 $((timestamp - DATA_TTL)) >/dev/null

    # Fetch workers data
    workers=$(curl -s $headers "http://${PROXY_HOST}:${PROXY_PORT}/1/workers")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch workers data"
        return 1
    fi
    echo "$workers" | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -x SET "$WORKERS_KEY" EX "$DATA_TTL" >/dev/null

    # Fetch miners data
    miners=$(curl -s $headers "http://${PROXY_HOST}:${PROXY_PORT}/1/miners")
    if [ $? -ne 0 ]; then
        echo "Error: Failed to fetch miners data"
        return 1
    fi
    echo "$miners" | redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -x SET "$MINERS_KEY" EX "$DATA_TTL" >/dev/null

    echo "Stats updated at $(date)"
}

# Function to display current stats
display_stats() {
    # Retrieve data from Redis
    summary=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$SUMMARY_KEY")
    workers=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$WORKERS_KEY")
    miners=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$MINERS_KEY")

    if [ -z "$summary" ]; then
        echo "No stats available in Redis"
        return 1
    fi

    # Format hashrate
    format_hashrate() {
        local hashrate=$1
        if [ $(echo "$hashrate >= 1000" | bc -l) -eq 1 ]; then
            printf "%.2f MH/s" $(echo "$hashrate / 1000" | bc -l)
        elif [ $(echo "$hashrate >= 1" | bc -l) -eq 1 ]; then
            printf "%.2f kH/s" "$hashrate"
        else
            printf "%.2f H/s" "$hashrate"
        fi
    }

    # Format difficulty
    format_difficulty() {
        local difficulty=$1
        if [ $(echo "$difficulty >= 1000000" | bc -l) -eq 1 ]; then
            printf "%.2fM" $(echo "$difficulty / 1000000" | bc -l)
        elif [ $(echo "$difficulty >= 1000" | bc -l) -eq 1 ]; then
            printf "%.1fK" $(echo "$difficulty / 1000" | bc -l)
        else
            echo "$difficulty"
        fi
    }

    # Format uptime
    format_uptime() {
        local seconds=$1
        local hours=$((seconds / 3600))
        local minutes=$(( (seconds % 3600) / 60 ))
        local secs=$((seconds % 60))
        if [ $hours -gt 0 ]; then
            echo "${hours}h ${minutes}m"
        elif [ $minutes -gt 0 ]; then
            echo "${minutes}m ${secs}s"
        else
            echo "${secs}s"
        fi
    }

    # Display summary stats
    echo "XMRig Proxy Stats"
    echo "================="
    echo "Connected Workers: $(echo "$summary" | jq -r '.miners.now // .workers // 0')"
    echo "Accepted Shares: $(echo "$summary" | jq -r '.results.accepted // 0')"
    echo "Uptime: $(format_uptime $(echo "$summary" | jq -r '.uptime // 0'))"
    echo "Active Upstreams: $(echo "$summary" | jq -r '.upstreams.active // 0')"
    echo "Current Hashrate: $(format_hashrate $(echo "$summary" | jq -r '.hashrate.total[0] // 0'))"

    # Display workers
    echo -e "\nActive Workers:"
    echo "ID | IP Address | Accepted | Rejected | Difficulty | 10m Rate | 24h Rate"
    echo "--------------------------------------------------------------------------------"

    if [ -n "$workers" ] && [ "$(echo "$workers" | jq -r '.workers | length')" -gt 0 ]; then
        echo "$workers" | jq -r '.workers[] | select(.[2] > 0) | @tsv' | while IFS=$'\t' read -r id ip connections accepted rejected _ _ _ _ hashrate10m _ _ hashrate24h; do
            # Find matching miner for difficulty
            difficulty="N/A"
            if [ -n "$miners" ]; then
                difficulty=$(echo "$miners" | jq -r --arg ip "$ip" --arg id "$id" '.miners[] | select(.["1"] == $ip or .["8"] == $id) | .["5"] // "N/A"')
                [ "$difficulty" != "N/A" ] && difficulty=$(format_difficulty "$difficulty")
            fi

            printf "%s | %s | %s | %s | %s | %s | %s\n" \
                "$id" "$ip" "$accepted" "$rejected" "$difficulty" \
                "$(format_hashrate "$hashrate10m")" "$(format_hashrate "$hashrate24h")"
        done
    else
        echo "No active workers with connections"
    fi

    # Display recent hashrate history
    echo -e "\nRecent Hashrate History (last 10 points):"
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ZREVRANGE "$HASHRATE_HISTORY_KEY" 0 9 WITHSCORES | while read -r hashrate timestamp; do
        echo "$(date -d "@$timestamp") : $(format_hashrate "$hashrate")"
    done
}

# Main loop
main() {
    echo "Starting XMRig stats collection..."
    while true; do
        fetch_and_store_stats
        sleep "$UPDATE_INTERVAL"
    done
}

# Command-line interface
case "$1" in
    display)
        display_stats
        ;;
    *)
        main
        ;;
esac

