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
    src/AppDelegate+Updater.swift \
    src/ClaudeUsage.swift \
    src/UsageCore.swift \
    src/UsageBreakdownCore.swift \
    src/ClaudeCodeTranscripts.swift \
    src/CodexUsageCore.swift \
    src/CodexOverageCore.swift \
    src/OpencodeUsageCore.swift \
    src/UpdateCore.swift \
    src/api/GitHubUpdateAPI.swift \
    -framework Cocoa -framework Carbon -framework ServiceManagement -framework WebKit

# Record where this build came from, for the in-app updater (Help > Check for Updates...).
# Outside a git checkout of this repo these keys are omitted and the updater stays off.
UPDATE_KEYS=""
CLONE_PATH=$(git rev-parse --show-toplevel 2>/dev/null || true)
# Compare against this directory, so a download sitting inside some other repo is not mistaken for a clone.
if [ "$CLONE_PATH" = "$(pwd -P)" ] && COMMIT=$(git rev-parse HEAD 2>/dev/null); then
    UPDATE_BRANCH="${CLAUDEUSAGE_UPDATE_BRANCH:-master}"
    xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<< "$1"; }
    UPDATE_KEYS="    <key>ClaudeUsageCommit</key>
    <string>$COMMIT</string>
    <key>ClaudeUsageClonePath</key>
    <string>$(xml_escape "$CLONE_PATH")</string>
    <key>ClaudeUsageUpdateBranch</key>
    <string>$(xml_escape "$UPDATE_BRANCH")</string>"
fi

# Create Info.plist
cat > ClaudeUsage.app/Contents/Info.plist << EOF
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
$UPDATE_KEYS
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

plutil -lint -s ClaudeUsage.app/Contents/Info.plist

echo "Done! Run with: open ClaudeUsage.app"
