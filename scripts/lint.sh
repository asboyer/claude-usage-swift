#!/bin/bash
set -euo pipefail

swift format lint --recursive \
    src \
    tests
