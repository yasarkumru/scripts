#!/bin/bash

# Define the downloads and history directories
DOWNLOADS_DIR="$HOME/Downloads"
HISTORY_DIR="$DOWNLOADS_DIR/history"

# Check if directory exists
if [ ! -d "$DOWNLOADS_DIR" ]; then
    echo "Downloads directory not found: $DOWNLOADS_DIR"
    exit 1
fi

# Ensure history directory exists
mkdir -p "$HISTORY_DIR"

# Get the previous month and year (e.g., 2023-October)
# LC_TIME=C ensures the month name is in English
PREV_MONTH_NAME=$(LC_TIME=C date -d "last month" +"%Y-%B")
TARGET_DIR="$HISTORY_DIR/$PREV_MONTH_NAME"

# Check if the folder for the previous month already exists
if [ -d "$TARGET_DIR" ]; then
    echo "Archive for $PREV_MONTH_NAME already exists. Skipping."
    exit 0
fi

# Check if there are any files/folders to move (excluding the history directory and .directory)
FILES_TO_MOVE=$(find "$DOWNLOADS_DIR" -maxdepth 1 -not -path "$DOWNLOADS_DIR" -not -path "$HISTORY_DIR" -not -name ".directory" -print -quit)

if [ -n "$FILES_TO_MOVE" ]; then
    # Create the target directory for the previous month
    mkdir -p "$TARGET_DIR"

    # Move all items from Downloads into the new monthly folder
    find "$DOWNLOADS_DIR" -maxdepth 1 \
        -not -path "$DOWNLOADS_DIR" \
        -not -path "$HISTORY_DIR" \
        -not -name ".directory" \
        -exec mv {} "$TARGET_DIR/" \;

    # Send a desktop notification that stays in the notification center
    notify-send \
        --icon=folder-download \
        -a "Download Organizer" \
        --hint=string:desktop-entry:org.kde.dolphin \
        "Monthly Cleanup Complete" \
        "Previous month's files moved to history/$PREV_MONTH_NAME"

    echo "Previous month's downloads organized into: $TARGET_DIR"
else
    echo "No files to organize for $PREV_MONTH_NAME."
fi
