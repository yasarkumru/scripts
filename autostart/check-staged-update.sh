#!/usr/bin/env bash

while true; do
    if rpm-ostree status --json | jq -e '.deployments[] | select(.staged == true)' >/dev/null 2>&1; then
        notify-send \
            --icon=system-software-update \
            -a "System Update" \
            --hint=string:desktop-entry:systemsettings \
            "System Update Ready" \
            "A system update is staged. Reboot to apply it."
        sleep 1d
    else
        sleep 1h
    fi
done
