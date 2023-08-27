#!/bin/bash

# Root paths for your applications and configs
SWAG_ROOT="/root/apps/swag/config"
SCRIPT_DIR="$SWAG_ROOT/log/extract_failed_ips"

# Derived paths from the root paths
NGINX_LOG_PATH="$SWAG_ROOT/log/nginx"

# Apps and their suspected login URL endpoints
declare -A APPS=(
    ["radarr"]="/radarr/login"
    ["sonarr"]="/sonarr/login"
    ["qbittorrent"]="/qbittorrent/login"
    ["prowlarr"]="/prowlarr/login"
    ["sabnzbd"]="/sabnzbd/login"
)

# File A: Output file where the new IPs from the log are stored
A="$SCRIPT_DIR/failed_ips.txt"

# File B: Previously added IPs
B="$SCRIPT_DIR/previously_added_ips.txt"

# Temp file for new IPs to be added
TMP_NEW_IPS="/tmp/new_ips.txt"

# If B does not exist, create an empty one
[ ! -f "$B" ] && touch "$B"

# Get the IP address of the SSH client logged in as 'root'
exclude_ip=$(who | grep root | awk '{print $5}' | tail -1 | tr -d '()')
[ -z "$exclude_ip" ] && exclude_ip="0.0.0.0"  # Fallback to dummy IP

# Empty file A
> "$A"

# Extract IPs from Nginx logs for unauthorized access and add them to file A
for log_file in ${NGINX_LOG_PATH}/access.log*; do
    # If log file is gzipped, use zcat to read, otherwise cat
    cat_cmd="cat"
    if [[ "$log_file" == *.gz ]]; then
        cat_cmd="zcat"
    fi

    for app in "${!APPS[@]}"; do
        endpoint=${APPS[$app]}
        $cat_cmd "$log_file" | grep "$endpoint" | grep ' 401\| 403' | awk '{print $1}' | grep -v "$exclude_ip" >> "$A"
    done
done

# Remove duplicates from A
sort -u "$A" -o "$A"

# Find IPs that are in A but not in B (new IPs to be added)
comm -23 <(sort $A) <(sort $B) > $TMP_NEW_IPS

# Add new IPs to the firewall and update B
while IFS= read -r ip; do
    # Check if the rule already exists to avoid adding it multiple times
    if ! ufw status verbose | grep -q "$ip"; then
        ufw reject from "$ip" to any
        echo $ip >> $B
    fi
done < $TMP_NEW_IPS

# Activate the changes
ufw reload
