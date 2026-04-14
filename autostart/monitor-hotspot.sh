#!/usr/bin/env bash

# monitor-hotspot.sh - Real-time hotspot device monitor using iw events
# Detects connects/disconnects instantly via kernel wireless events.
# Usage: ./monitor-hotspot.sh [interface] (default: wlp0s20f3)

# Auto-detect the interface running in AP (hotspot) mode, or use the argument
if [[ -n "$1" ]]; then
    INTERFACE="$1"
else
    INTERFACE=$(iw dev | awk '/Interface/{iface=$2} /type AP/{print iface}' | head -1)
fi

notify() {
    local summary="$1"
    local body="$2"
    local icon="$3"
    notify-send \
        -a "Hotspot Monitor" \
        -i "$icon" \
        --hint=string:desktop-entry:kcm_networkmanagement \
        "$summary" "$body"
}

get_ip_for_mac() {
    local mac="$1"
    local ip=""

    # ARP/neighbor table is the most up-to-date source
    ip=$(ip neigh show dev "$INTERFACE" 2>/dev/null \
        | grep -i "$mac" | awk '{print $1}' | head -1)

    echo "$ip"
}

get_hostname_for_mac() {
    local mac="$1"
    local ip="$2"
    local hostname=""

    # 1. mDNS (.local) via avahi-resolve — works for phones, laptops, most modern devices
    if [[ -n "$ip" ]] && command -v avahi-resolve &>/dev/null; then
        hostname=$(avahi-resolve --address "$ip" 2>/dev/null \
            | awk '{print $2}' | sed 's/\.local\.*//')
    fi

    # 2. Reverse DNS via getent
    if [[ -z "$hostname" && -n "$ip" ]]; then
        hostname=$(getent hosts "$ip" 2>/dev/null | awk '{print $2}' | head -1)
    fi

    echo "$hostname"
}

resolve_ip_with_retry() {
    local mac="$1"
    local ip=""
    local attempts=5

    for ((i = 1; i <= attempts; i++)); do
        ip=$(get_ip_for_mac "$mac")
        [[ -n "$ip" ]] && break
        sleep 1
    done

    echo "$ip"
}

# Sanity checks
if ! command -v iw &>/dev/null; then
    echo "Error: 'iw' not found. Install iw (iw package)."
    exit 1
fi

if [[ -z "$INTERFACE" ]]; then
    echo "Error: No hotspot interface found. Is the hotspot active?"
    echo "Usage: $0 [interface]"
    exit 1
fi

if ! ip link show "$INTERFACE" &>/dev/null; then
    echo "Error: Interface '$INTERFACE' not found."
    echo "Usage: $0 [interface]"
    exit 1
fi

echo "Monitoring hotspot on $INTERFACE (real-time via iw events)"
echo "Press Ctrl+C to stop."
echo ""

iw event 2>/dev/null | while IFS= read -r line; do

    # iw event format:
    #   <timestamp>: <iface>: new station <mac>
    #   <timestamp>: <iface>: del station <mac>

    if [[ "$line" =~ ${INTERFACE}:\ new\ station\ ([0-9a-fA-F:]{17}) ]]; then
        mac="${BASH_REMATCH[1]}"

        # Give DHCP a moment to assign an IP, then retry a few times
        ip=$(resolve_ip_with_retry "$mac")
        hostname=$(get_hostname_for_mac "$mac" "$ip")

        detail="MAC: $mac"
        [[ -n "$ip" ]]       && detail+="\nIP: $ip"

        title="Device connected"
        [[ -n "$hostname" ]] && title="$hostname connected"

        notify "$title" "$detail" "network-wireless-connected-100"
        echo "[$(date '+%H:%M:%S')] CONNECTED    $detail"

    elif [[ "$line" =~ ${INTERFACE}:\ del\ station\ ([0-9a-fA-F:]{17}) ]]; then
        mac="${BASH_REMATCH[1]}"

        # IP is likely gone from ARP by now; lean on lease file
        ip=$(get_ip_for_mac "$mac")
        hostname=$(get_hostname_for_mac "$mac" "$ip")

        detail="MAC: $mac"
        [[ -n "$ip" ]]       && detail+="\nIP: $ip"

        title="Device disconnected"
        [[ -n "$hostname" ]] && title="$hostname disconnected"

        notify "$title" "$detail" "network-wireless-disconnected"
        echo "[$(date '+%H:%M:%S')] DISCONNECTED $detail"
    fi

done
