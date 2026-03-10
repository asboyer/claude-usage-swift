#!/bin/bash
# Build Claude Usage Tracker

set -e

echo "Building ClaudeUsage..."

# Create app bundle structure
mkdir -p ClaudeUsage.app/Contents/MacOS

# Copy app icon
mkdir -p ClaudeUsage.app/Contents/Resources
cp AppIcon.icns ClaudeUsage.app/Contents/Resources/AppIcon.icns

# Compile
swiftc -O -o ClaudeUsage.app/Contents/MacOS/ClaudeUsage ClaudeUsage.swift -framework Cocoa -framework Carbon -framework ServiceManagement -framework WebKit

# Create Info.plist if not exists
if [ ! -f ClaudeUsage.app/Contents/Info.plist ]; then
cat > ClaudeUsage.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsage</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude.usage-tracker</string>
    <key>CFBundleName</key>
    <string>Claude Usage</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF
fi

echo "Done! Run with: open ClaudeUsage.app"
