#!/bin/bash

# monitor-hotspot.sh - Real-time hotspot device monitor using iw events
# Detects connects/disconnects instantly via kernel wireless events.
# Works even if the hotspot is started after this script; never misses events.
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

is_ap_interface() {
    local iface="$1"
    iw dev 2>/dev/null | awk -v i="$iface" '
        /Interface/ { cur = $2 }
        cur == i && /type AP/ { found = 1 }
        END { exit !found }
    '
}

if ! command -v iw &>/dev/null; then
    echo "Error: 'iw' not found. Install iw (iw package)."
    exit 1
fi

echo "Listening for hotspot events (hotspot does not need to be active yet)"

# Debounce: suppress duplicate same-type events for the same MAC within this window
declare -A LAST_EVENT_TIME
DEBOUNCE_SECONDS=3

# Pending disconnect notifications: mac -> PID of delayed background job
declare -A PENDING_DISCONNECT
# Delay before firing a disconnect notification; cancelled if device reconnects
DISCONNECT_DELAY=2

while true; do
    # Run iw event continuously — it captures events regardless of hotspot state
    coproc IW_EVENT { iw event 2>/dev/null; }

    while IFS= read -r line <&"${IW_EVENT[0]}" 2>/dev/null; do

        # iw event format:
        #   <iface>: new station <mac>
        #   <iface>: del station <mac>
        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):\ (new|del)\ station\ ([0-9a-fA-F:]{17}) ]]; then
            event_iface="${BASH_REMATCH[1]}"
            event_type="${BASH_REMATCH[2]}"
            mac="${BASH_REMATCH[3]}"

            # Debounce: skip if same event type for this MAC fired recently
            now=$(date +%s)
            key="${mac}_${event_type}"
            last_time="${LAST_EVENT_TIME[$key]:-0}"
            if (( now - last_time < DEBOUNCE_SECONDS )); then
                continue
            fi
            LAST_EVENT_TIME[$key]="$now"

            # If a specific interface was requested, ignore others
            if [[ -n "$INTERFACE_ARG" && "$event_iface" != "$INTERFACE_ARG" ]]; then
                continue
            fi

            # Only handle interfaces currently in AP (hotspot) mode
            is_ap_interface "$event_iface" || continue

            INTERFACE="$event_iface"

            if [[ "$event_type" == "new" ]]; then
                # Cancel any pending disconnect notification for this MAC —
                # it was a brief drop during reassociation, not a real disconnect
                if [[ -n "${PENDING_DISCONNECT[$mac]}" ]]; then
                    kill "${PENDING_DISCONNECT[$mac]}" 2>/dev/null
                    unset "PENDING_DISCONNECT[$mac]"
                fi

                # Give DHCP a moment to assign an IP, then retry a few times
                ip=$(resolve_ip_with_retry "$mac")
                hostname=$(get_hostname_for_mac "$mac" "$ip")

                detail="MAC: $mac"
                [[ -n "$ip" ]]       && detail+="\nIP: $ip"

                title="Device connected"
                [[ -n "$hostname" ]] && title="$hostname connected"

                notify "$title" "$detail" "network-wireless-connected-100"

            else
                # Delay the disconnect notification; a reconnect within
                # DISCONNECT_DELAY seconds will cancel it (reassociation race)
                captured_iface="$event_iface"
                captured_mac="$mac"
                (
                    sleep "$DISCONNECT_DELAY"
                    INTERFACE="$captured_iface"
                    ip=$(get_ip_for_mac "$captured_mac")
                    hostname=$(get_hostname_for_mac "$captured_mac" "$ip")

                    detail="MAC: $captured_mac"
                    [[ -n "$ip" ]]       && detail+="\nIP: $ip"

                    title="Device disconnected"
                    [[ -n "$hostname" ]] && title="$hostname disconnected"

                    notify "$title" "$detail" "network-wireless-disconnected"
                ) &
                PENDING_DISCONNECT[$mac]=$!
            fi
        fi

    done

    # iw event exited unexpectedly — restart after a brief pause
    kill "$IW_EVENT_PID" 2>/dev/null
    pkill -P "$IW_EVENT_PID" 2>/dev/null
    wait "$IW_EVENT_PID" 2>/dev/null
    sleep 5
done