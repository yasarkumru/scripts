#!/bin/bash

REPO_DIR="$HOME/scripts"

# Force sync with the remote to avoid merge conflicts from local changes (like chmod)
if [ -d "$REPO_DIR/.git" ]; then
    timeout 30s bash -c "git -C '$REPO_DIR' fetch --quiet && git -C '$REPO_DIR' checkout origin/main -- autostart/" || true
fi

for script in "$REPO_DIR/autostart"/*.sh; do
    if [[ -f "$script" ]]; then
        chmod +x "$script"
        # Kill any already-running instances before starting a fresh one
        pkill -f "$script" 2>/dev/null
        # Run in background, redirect output to null, and disown to prevent blocking logout
        "$script" >/dev/null 2>&1 &
        disown
    fi
done
