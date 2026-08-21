#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/stand"
PLIST_NAME="com.user.stand"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

# Configurable defaults (edit these or override via launchd plist)
STAND_INTERVAL="${STAND_INTERVAL:-3000}"
STAND_DURATION="${STAND_DURATION:-600}"
STAND_TRAINING_EVERY="${STAND_TRAINING_EVERY:-3}"

echo "Compiling..."
swiftc "$SCRIPT_DIR/stand.swift" -o "$BINARY" -framework Cocoa

echo "Installing launch agent..."

# Unload existing agent if present
if launchctl list | grep -q "$PLIST_NAME"; then
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>STAND_INTERVAL</key>
        <string>$STAND_INTERVAL</string>
        <key>STAND_DURATION</key>
        <string>$STAND_DURATION</string>
        <key>STAND_TRAINING_EVERY</key>
        <string>$STAND_TRAINING_EVERY</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/stand.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/stand.log</string>
</dict>
</plist>
EOF

launchctl load "$PLIST_PATH"

echo ""
echo "Installed and running."
echo "  Sit interval:   $((STAND_INTERVAL / 60)) min"
echo "  Stand duration: $((STAND_DURATION / 60)) min"
echo "  Training set:   every $STAND_TRAINING_EVERY transitions"
echo ""
echo "To reconfigure, edit values and re-run install.sh:"
echo "  STAND_INTERVAL=1800 STAND_TRAINING_EVERY=4 ./install.sh"
echo ""
echo "To uninstall:"
echo "  ./uninstall.sh"
