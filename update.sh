#!/bin/bash
# Rebuild and reinstall ClaudeUsage.app from this clone.
set -e
cd "$(cd "$(dirname "$0")" && pwd)"

killall ClaudeUsage 2>/dev/null || true
rm -rf /Applications/ClaudeUsage.app
./build.sh
mv ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
