#!/bin/bash

# setup_scx_headers_fixed.sh - Fixed version for git sparse checkout

set -e

SCX_DIR="./scx"
TEMP_DIR="./temp_scx_clone"

# Clean up old directories
rm -rf "$SCX_DIR" "$TEMP_DIR"

echo "Cloning repository (shallow clone)..."
git clone --depth 1 https://github.com/sched-ext/scx.git "$TEMP_DIR"

echo "Copying headers..."
mkdir -p "$SCX_DIR"
cp -r "$TEMP_DIR/scheds/include/scx/"* "$SCX_DIR/"

# Clean up
rm -rf "$TEMP_DIR"

echo "✓ scx headers installed in $SCX_DIR/"
echo "Contents:"
ls -la "$SCX_DIR/"
