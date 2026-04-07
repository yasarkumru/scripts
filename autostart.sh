#!/usr/bin/env bash

REPO_DIR="/var/home/yasar/scripts"

# Pull latest changes once at start. If it fails, continue anyway.
if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --quiet || true
fi

for script in "$REPO_DIR/autostart"/*; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        "$script" &
    fi
done
