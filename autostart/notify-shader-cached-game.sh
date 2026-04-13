#!/bin/bash

last_appid=""

while true; do
    # Added -f to search the full command line and bypass the 15-character limit
    # Using [f] prevents the script from accidentally finding its own pgrep process
    cmd=$(pgrep -a -f "[f]ossilize_replay" | head -n 1)
    
    if [ -n "$cmd" ]; then
        # Extract the AppID
        current_appid=$(echo "$cmd" | grep -oP 'shadercache/\K\d+' | head -n 1)
        
        # Check if we found an AppID and if it is different from the last checked one
        if [ -n "$current_appid" ] && [ "$current_appid" != "$last_appid" ]; then
            last_appid="$current_appid"
            
            # Find the appmanifest to get the game name
            manifest=$(find ~/.local/share/Steam/steamapps ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps -maxdepth 1 -name "appmanifest_${current_appid}.acf" 2>/dev/null | head -n 1)
            
            if [ -n "$manifest" ]; then
                game_name=$(grep -E '"name"\s+' "$manifest" | cut -d\" -f4)
                notify-send \
                    -i steam \
                    -a "Steam" \
                    --hint=string:desktop-entry:steam \
                    "Steam Shaders" \
                    "Building shaders for: $game_name"
            else
                notify-send \
                    -i steam \
                    -a "Steam" \
                    --hint=string:desktop-entry:steam \
                    "Steam Shaders" \
                    "Building shaders for AppID: $current_appid"
            fi
        fi
    else
        # Reset if no process is running, so it notifies properly next time it starts
        last_appid=""
    fi
    
    # Wait 5 seconds before checking again
    sleep 5
done