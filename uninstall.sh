#!/bin/bash

PLIST_NAME="com.user.stand"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm "$PLIST_PATH"
    echo "Uninstalled."
else
    echo "Not installed."
fi
