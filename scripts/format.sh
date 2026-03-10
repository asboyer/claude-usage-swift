#!/bin/bash
set -euo pipefail

swift format --in-place --recursive \
    src \
    tests
