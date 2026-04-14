#!/bin/bash

REPO_DIR="$HOME/scripts"
AUTOSTART_DIR="$REPO_DIR/autostart"

killed=0
for script in "$AUTOSTART_DIR"/*.sh; do
    [[ -f "$script" ]] || continue
    if pkill -f "$script" 2>/dev/null; then
        echo "Killed: $(basename "$script")"
        ((killed++))
    fi
done

if ((killed == 0)); then
    echo "No autostart scripts were running."
else
    echo "Stopped $killed script(s)."
fi