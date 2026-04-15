#!/bin/bash

# monitor-hotspot.sh - Real-time hotspot device monitor using iw events
# Detects connects/disconnects instantly via kernel wireless events.
# Polls every 5 minutes when no hotspot is active, then starts monitoring.
# Usage: ./monitor-hotspot.sh [interface] (default: auto-detect)

INTERFACE_ARG="$1"

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
    ip neigh show dev "$INTERFACE" 2>/dev/null \
        | grep -i "$mac" | awk '{print $1}' | head -1
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

find_ap_interface() {
    if [[ -n "$INTERFACE_ARG" ]]; then
        ip link show "$INTERFACE_ARG" &>/dev/null && echo "$INTERFACE_ARG"
    else
        iw dev | awk '/Interface/{iface=$2} /type AP/{print iface}' | head -1
    fi
}

if ! command -v iw &>/dev/null; then
    echo "Error: 'iw' not found. Install iw (iw package)."
    exit 1
fi

while true; do
    INTERFACE=$(find_ap_interface)

    if [[ -z "$INTERFACE" ]]; then
        sleep 300
        continue
    fi

    echo "Monitoring hotspot on $INTERFACE (real-time via iw events)"

    # Use coproc so we can kill iw event if the hotspot is turned off
    coproc IW_EVENT { iw event 2>/dev/null; }

    while true; do
        # Check every 60s (read timeout) that the hotspot is still active
        current=$(find_ap_interface)
        if [[ -z "$current" ]]; then
            kill "$IW_EVENT_PID" 2>/dev/null
            wait "$IW_EVENT_PID" 2>/dev/null
            break
        fi

        # iw event format:
        #   <timestamp>: <iface>: new station <mac>
        #   <timestamp>: <iface>: del station <mac>
        IFS= read -r -t 60 line <&"${IW_EVENT[0]}" 2>/dev/null || continue

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
        fi
    done

    # Hotspot went away; poll until it comes back
    sleep 300
done
