#!/bin/bash

# Exit on any error
set -e

# Update and install dependencies
apt update -y && apt upgrade -y
pkg install nano git build-essential cmake tmux -y || { echo "Failed to install dependencies"; exit 1; }

# Clone xmrig
git clone https://github.com/MoneroOcean/xmrig.git || { echo "Failed to clone xmrig repository"; exit 1; }

# Disable donations like a bastard
sed -i -e 's/kDefaultDonateLevel = 1/kDefaultDonateLevel = 0/' -e 's/kMinimumDonateLevel = 1/kMinimumDonateLevel = 0/' xmrig/src/donate.h

# Create directories
mkdir -p ~/xmrig/build ~/xmrig.mo || { echo "Failed to create directories"; exit 1; }

# Build xmrig
cd ~/xmrig/build
cmake .. -DWITH_HWLOC=OFF && make -j$(nproc) || { echo "Build failed"; exit 1; }
cp xmrig ~/xmrig.mo/

# Make run.sh
cd ~/
cat << 'EOF' > run.sh
#!/bin/bash

# Check if directory and files exist
cd ~/xmrig.mo || { echo "Error: Directory ~/xmrig.mo not found!"; exit 1; }
if [ ! -f xmrig ]; then
    echo "Error: xmrig binary not found in ~/xmrig.mo!"
    exit 1
fi
if [ ! -f config.json ]; then
    echo "Error: config.json not found in ~/xmrig.mo!"
    exit 1
fi

# Run xmrig in a tmux session, logging output
if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux not installed. Running xmrig in foreground."
    ./xmrig $@
else
    tmux new-session -s xmrig ./xmrig $@
    echo "xmrig started in tmux session 'xmrig'. Reattach with: tmux attach -t xmrig"
fi

cd ..

EOF
chmod +x run.sh

# Configure xmrig
cp xmrig/src/config.json ~/xmrig.mo/ || { echo "Failed to copy config.json"; exit 1; }
cp xmrig.mo/config.json xmrig.mo/config.json.bak # Backup config
sed -i -e 's/"donate-level": 1,/"donate-level": 0,/' -e 's/"cache_qos": false,/"cache_qos": true,/' -e 's/"url": "gulf.moneroocean.stream:10128",/"url": "192.168.8.18:3333",/' -e 's/"nicehash": false,/"nicehash": true,/' -e 's/"yield": true,/"yield": false,/' xmrig.mo/config.json

# Prompt for hostname and update config
read -p "Enter short hostname: " hostname
if [ -z "$hostname" ]; then
    echo "Error: Hostname cannot be empty!"
    exit 1
fi
sed -i -e "s/\"user\": \"YOUR_WALLET_ADDRESS\",/\"user\": \"$hostname\",/" -e "s/\"pass\": \"x\",/\"pass\": \"$hostname\",/" -e "s/\"rig-id\": null,/\"rig-id\": \"$hostname\",/" xmrig.mo/config.json

echo "Setup complete! Run xmrig with: bash ~/run.sh"

