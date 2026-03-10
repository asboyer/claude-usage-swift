#!/bin/bash
set -euo pipefail

swift format --in-place --recursive ClaudeUsage.swift Sources Tests
