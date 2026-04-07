#!/usr/bin/env bash

REPO_DIR="/var/home/yasar/scripts"

# Force sync with the remote to avoid merge conflicts from local changes (like chmod)
if [ -d "$REPO_DIR/.git" ]; then
    timeout 30s bash -c "git -C $REPO_DIR fetch --quiet && git -C $REPO_DIR reset --hard origin/main --quiet" || true
fi

for script in "$REPO_DIR/autostart"/*.sh; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        "$script" &
    fi
done
