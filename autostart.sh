#!/usr/bin/env bash

for script in /home/yasar/scripts/autostart/*; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        bash "$script" &
    fi
done
