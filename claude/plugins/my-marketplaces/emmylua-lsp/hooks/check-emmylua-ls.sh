#!/bin/bash

if command -v emmylua_ls &> /dev/null; then
    # emmylua_ls is installed, exit silently
    exit 0
fi

echo "[emmylua_ls] Not installed. Please download from: https://github.com/EmmyLuaLs/emmylua-analyzer-rust/releases"

exit 0
