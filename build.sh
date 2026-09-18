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
swiftc -O -o ClaudeUsage.app/Contents/MacOS/ClaudeUsage \
    src/main.swift \
    src/AppConstants.swift \
    src/KeychainCredentials.swift \
    src/api/UsageAPIModels.swift \
    src/history/UsageHistoryStore.swift \
    src/graph/UsageBreakdownPage.swift \
    src/api/ClaudeDesktopUsageAPI.swift \
    src/api/OAuthUsageAPI.swift \
    src/api/CodexUsageAPI.swift \
    src/api/CursorUsageAPI.swift \
    src/api/OpencodeUsageAPI.swift \
    src/TimeFormatting.swift \
    src/SoundPlayback.swift \
    src/AppDelegate+MenuAndRefresh.swift \
    src/ClaudeUsage.swift \
    src/UsageCore.swift \
    src/UsageBreakdownCore.swift \
    src/ClaudeCodeTranscripts.swift \
    src/CodexUsageCore.swift \
    src/OpencodeUsageCore.swift \
    -framework Cocoa -framework Carbon -framework ServiceManagement -framework WebKit

# Create Info.plist
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
    <key>CFBundleGetInfoString</key>
    <string>Author: asboyer</string>
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

# Sign with a stable identity so keychain "Always Allow" grants survive a rebuild.
# An ad-hoc signature has no durable designated requirement, so macOS pins the grant to the
# exact build hash and re-prompts on the next build. See README > Keychain prompts.
IDENTITY="${CLAUDEUSAGE_SIGN_IDENTITY:-ClaudeUsage Local Signing}"
if security find-identity -v -p codesigning | grep -qF "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier com.claude.usage-tracker ClaudeUsage.app
    echo "Signed with: $IDENTITY"
else
    echo "warning: no codesigning identity named '$IDENTITY'; leaving the ad-hoc signature."
    echo "         Keychain access will be re-prompted after every rebuild."
    echo "         See README > Keychain prompts to create one."
fi

echo "Done! Run with: open ClaudeUsage.app"
