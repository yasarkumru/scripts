#!/usr/bin/env bash
 
FLAG_FILE="/tmp/staged-update-notified"
rm -f "$FLAG_FILE"
 
while true; do
    STATUS=$(rpm-ostree status 2>/dev/null)
    BEFORE_BOOTED=$(echo "$STATUS" | sed '/^●/q' | head -n -1)
 
    if echo "$BEFORE_BOOTED" | grep -q "Version:"; then
        if [[ ! -f "$FLAG_FILE" ]] || (( $(date +%s) - $(cat "$FLAG_FILE") > 86400 )); then
            STAGED_VERSION=$(echo "$BEFORE_BOOTED" | grep "Version:" | awk '{print $2}')
            notify-send \
                --icon=system-software-update \
                -a "System Update" \
                --hint=string:desktop-entry:systemsettings \
                "System Update Ready" \
                "Version $STAGED_VERSION is staged. Reboot to apply it."
            date +%s > "$FLAG_FILE"
        fi
    fi
    sleep 1h
done
