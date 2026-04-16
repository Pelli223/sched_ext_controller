#!/bin/bash

# setup_scx_headers_git.sh - Uses git sparse checkout to get only the headers

set -e

TEMP_DIR=$(mktemp -d)
SCX_DIR="scx"

echo "Cloning sched-ext/scx (sparse checkout)..."
cd "$TEMP_DIR"
git clone --depth 1 --filter=blob:none --sparse https://github.com/sched-ext/scx.git
cd scx
git sparse-checkout set scheds/include/scx

# Copy only the headers we need
mkdir -p "$OLDPWD/$SCX_DIR"
cp -r scheds/include/scx/* "$OLDPWD/$SCX_DIR/"

cd "$OLDPWD"
rm -rf "$TEMP_DIR"

echo "✓ scx headers copied to ./$SCX_DIR/"
ls -la "$SCX_DIR/"
