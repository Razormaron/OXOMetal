#!/bin/bash
# Builds OXOMetal and installs it as OXO.app in /Applications.
set -e
cd "$(dirname "$0")"

echo "Building..."
swift build -c release

APP="/Applications/OXO.app"
BINARY=".build/arm64-apple-macosx/release/OXOMetal"

# Create app bundle
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/OXO"
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

touch "$APP"
killall Dock 2>/dev/null || true

echo "Done — OXO.app installed in /Applications."
echo "You can also drag it to your Dock from there."
