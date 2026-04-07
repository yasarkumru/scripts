#!/usr/bin/env bash

REPO_DIR="/var/home/yasar/scripts"

# Pull latest changes once at start with a 30s timeout. If it fails or times out, continue anyway.
if [ -d "$REPO_DIR/.git" ]; then
    timeout 30s git -C "$REPO_DIR" pull --quiet || true
fi

for script in "$REPO_DIR/autostart"/*.sh; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        "$script" &
    fi
done
