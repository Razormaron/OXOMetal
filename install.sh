#!/bin/bash
# Builds OXO and creates OXO.app in this directory + installs to /Applications.
set -e
cd "$(dirname "$0")"

# Regenerate icon if the generator script is present
if [ -f generate_icon.swift ]; then
    echo "Generating icon..."
    swift generate_icon.swift
fi

echo "Building..."
swift build -c release

BINARY=".build/arm64-apple-macosx/release/OXOMetal"

bundle_app() {
    local APP="$1"
    mkdir -p "$APP/Contents/MacOS"
    mkdir -p "$APP/Contents/Resources"
    cp "$BINARY" "$APP/Contents/MacOS/OXO"
    chmod +x "$APP/Contents/MacOS/OXO"
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OXO</string>
    <key>CFBundleDisplayName</key><string>OXO</string>
    <key>CFBundleIdentifier</key><string>com.local.oxo</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>OXO</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
    # Strip quarantine so double-click works without Gatekeeper prompt
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
    touch "$APP"
}

# Build into repo directory (for GitHub distribution)
echo "Creating OXO.app in repo..."
bundle_app "OXO.app"

# Also install to /Applications
echo "Installing to /Applications..."
bundle_app "/Applications/OXO.app"
killall Dock 2>/dev/null || true

echo ""
echo "Done. OXO.app is in this folder and in /Applications."
echo "Double-click OXO.app to play, or drag it to your Dock."
