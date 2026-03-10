#!/bin/bash
set -euo pipefail

swift format lint --recursive ClaudeUsage.swift Sources Tests
