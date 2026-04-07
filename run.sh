#!/bin/bash

# Compile and run the stand reminder
# Configure via env vars:
#   STAND_INTERVAL=1500  (seconds between stand reminders, default 25 min)
#   STAND_DURATION=600   (seconds to stand for, default 10 min)
#   STAND_PHRASE="i will stand"  (phrase to type to dismiss, default "i will stand")
#
# Examples:
#   ./run.sh                          # defaults: 25min sit, 10min stand
#   STAND_INTERVAL=900 ./run.sh       # stand every 15 min
#   STAND_PHRASE="get up" ./run.sh    # custom dismiss phrase

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/.stand_binary"

echo "Compiling..."
swiftc "$SCRIPT_DIR/stand.swift" -o "$BINARY" -framework Cocoa -framework AVFoundation 2>&1

if [ $? -ne 0 ]; then
    echo "Compilation failed."
    exit 1
fi

echo "Starting stand reminder..."
exec "$BINARY"
