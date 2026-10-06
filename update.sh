#!/bin/bash
# Rebuild and reinstall ClaudeUsage.app from this clone.
# Builds first, so a failed build leaves the installed app untouched and running.
set -e
cd "$(cd "$(dirname "$0")" && pwd)"

./build.sh

killall ClaudeUsage 2>/dev/null || true
# Wait for the old app to exit, or `open` may just reactivate it instead of launching the new one.
for _ in $(seq 50); do
    pgrep -x ClaudeUsage >/dev/null || break
    sleep 0.1
done
rm -rf /Applications/ClaudeUsage.app
mv ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
