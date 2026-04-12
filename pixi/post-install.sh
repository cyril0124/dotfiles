#!/usr/bin/env bash
# Pixi post-install hooks
# Define functions named post_install_<command> for each tool that needs initialization.
# The function is called only if <command> exists in PATH.

post_install_rtk() {
    rtk --version &>/dev/null || rtk init -g --opencode
}
