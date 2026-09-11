#!/bin/sh
# Entry for the tab-goto picker.
#
# Runs the C++ binary, rebuilding it first when a source file is newer than the
# binary, so edits take effect on the next invocation without a manual build.
# Falls back to the last good binary when a build fails, and to the Python
# plugin in ../tab-goto when there is no binary at all.
mode="${1:-picker}"
# Resolve the plugin root without forking dirname: herdr launches plugin
# commands with the plugin root as the working directory, so a bare "run.sh"
# argument resolves to the current directory.
dir=${0%/*}
[ "$dir" = "$0" ] && dir=.
dir="$(cd "$dir" && pwd)"
bin="$dir/tab-goto"

# True when the binary is missing or older than any source, header or the build
# script itself. A few stat calls, no extra process.
sources_changed() {
    [ -x "$bin" ] || return 0
    for src in "$dir"/src/*.cpp "$dir"/src/*.hpp "$dir"/build.sh; do
        [ "$src" -nt "$bin" ] && return 0
    done
    return 1
}

# Rebuilds the binary, allowing one build at a time. A stale lock left behind by
# a killed process is taken over once its owner is gone. A failed build keeps
# the previous binary, which is what runs below.
build_with_lock() {
    lock="$dir/build/.lock"
    mkdir -p "$dir/build" 2>/dev/null || return 0

    if ! mkdir "$lock" 2>/dev/null; then
        holder="$(cat "$lock/pid" 2>/dev/null)"
        if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
            return 0
        fi
        rm -rf "$lock"
        mkdir "$lock" 2>/dev/null || return 0
    fi
    printf '%s' "$$" >"$lock/pid"
    trap 'rm -rf "$lock"' EXIT INT TERM

    if ! sh "$dir/build.sh" build >"$dir/build/build.log" 2>&1; then
        echo "tab-goto-cpp: build failed, keeping the previous binary (see $dir/build/build.log)" >&2
    fi

    rm -rf "$lock"
    trap - EXIT INT TERM
}

if sources_changed; then
    build_with_lock
fi

if [ -x "$bin" ]; then
    exec "$bin" "$mode"
fi

# Stdlib-only startup; module mode reuses Python's bytecode cache.
cd "$dir/../tab-goto" || exit 1
case "$mode" in
    open) exec python3 -S -m open ;;
    *)    exec python3 -S -m picker ;;
esac
