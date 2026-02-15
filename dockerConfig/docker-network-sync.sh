#!/bin/sh

CONFIG_FILE="/etc/config/network"
BACKUP_FILE="/etc/config/network.bak.$(date +%Y%m%d%H%M%S)"

echo "🛡️  Backing up $CONFIG_FILE to $BACKUP_FILE ..."
cp "$CONFIG_FILE" "$BACKUP_FILE"

echo "🔍 Scanning Docker bridge networks..."

# Get existing interface devices from UCI
existing_devices=$(uci show network | grep ".device=" | cut -d'=' -f2 | tr -d "'\"")

# Process each Docker bridge network
docker network ls --format '{{.ID}} {{.Name}}' | while read -r id name; do
    driver=$(docker network inspect "$id" --format '{{.Driver}}')

    # Skip if not a bridge driver or is default 'bridge'
    if [ "$driver" = "bridge" ] && [ "$name" != "bridge" ]; then
        bridge_id="${id:0:12}"
        bridge_name="br-${bridge_id}"
        interface_name="${name}"

        if echo "$existing_devices" | grep -qx "$bridge_name"; then
            echo "🔹 Bridge '$bridge_name' already exists in config — skipping."
        else
            echo "➕ Adding Docker bridge '$bridge_name' as interface '$interface_name'..."

            uci add network interface
            uci set network.@interface[-1].proto='none'
            uci set network.@interface[-1].device="$bridge_name"

            # Optional: set section name equal to Docker network name
            # Note: requires identifying the last added section
            last_section=$(uci show network | grep "=interface" | tail -n1 | cut -d. -f2 | cut -d= -f1)
            uci rename network."$last_section"="$interface_name"
        fi
    fi
done

# Commit changes
echo "💾 Saving network config..."
uci commit network

echo "✅ Docker bridge sync complete."
echo "🚀 You can now run: /etc/init.d/network reload"

