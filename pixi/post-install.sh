#!/usr/bin/env bash
# Tool initialization and installation hooks
#
# Two types of functions:
#   post_install_<cmd>  - Called if <cmd> EXISTS in PATH (for initialization)
#   install_<tool>      - Called if <tool> NOT in PATH (for installation)

# ============================================
# Post-install hooks for pixi packages
# Function: post_install_<command>
# Called only if <command> exists in PATH
# ============================================

# ============================================
# Standalone tool installers
# Function: install_<tool>
# Called only if <tool> command NOT in PATH
# ============================================

install_uv() {
    curl -LsSf https://astral.sh/uv/install.sh | sh
}
