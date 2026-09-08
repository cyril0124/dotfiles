#!/bin/sh
# Entry for the tab-goto picker: run the Rust binary when built.
# Without a Rust toolchain, bootstrap skips the build and this script
# runs the Python plugin in ../tab-goto instead.
mode="${1:-picker}"
dir="$(cd "$(dirname "$0")" && pwd)"

if [ -x "$dir/tab-goto" ]; then
    exec "$dir/tab-goto" "$mode"
fi

# Stdlib-only startup; module mode reuses Python's bytecode cache.
cd "$dir/../tab-goto" || exit 1
case "$mode" in
    open) exec python3 -S -m open ;;
    *)    exec python3 -S -m picker ;;
esac
