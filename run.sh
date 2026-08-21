#!/bin/bash

# Compile and run the stand reminder
# Configure via env vars:
#   STAND_INTERVAL=3000       (seconds between stand reminders, default 50 min)
#   STAND_DURATION=600        (seconds to stand for, default 10 min)
#   STAND_TRAINING_EVERY=3    (every Nth transition is a training set)
#
# Examples:
#   ./run.sh                            # defaults: 50min sit, 10min stand
#   STAND_INTERVAL=1800 ./run.sh        # stand every 30 min
#   STAND_TRAINING_EVERY=4 ./run.sh     # training set every 4th transition

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
