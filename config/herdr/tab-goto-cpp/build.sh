#!/bin/sh
# Build the tab-goto picker. Needs a POSIX sh and a C++11 compiler. Usage:
#   ./build.sh          build ./tab-goto (recompiling only stale sources)
#   ./build.sh clean    remove build output
set -e

dir="$(cd "$(dirname "$0")" && pwd)"
cd "$dir"

out="tab-goto"
build_dir="build"
flags="${TAB_GOTO_CXXFLAGS:--O2 -std=gnu++11 -Wall -Wextra -Wpedantic}"

find_compiler() {
    if [ -n "${CXX:-}" ]; then
        printf '%s' "$CXX"
        return 0
    fi
    for candidate in c++ g++ clang++; do
        if command -v "$candidate" >/dev/null 2>&1; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

# Static C++ runtime cuts about a millisecond of startup on Linux, which matters
# for a popup this short-lived. macOS does not support these flags.
link_flags() {
    case "$(uname -s)" in
        Linux) printf '%s' "-static-libstdc++ -static-libgcc" ;;
        *)     printf '%s' "" ;;
    esac
}

# True when the object needs a rebuild: missing, older than its source, or older
# than any header.
needs_build() {
    obj="$1"
    src="$2"
    [ -f "$obj" ] || return 0
    [ "$src" -nt "$obj" ] && return 0
    for header in src/*.hpp; do
        [ "$header" -nt "$obj" ] && return 0
    done
    return 1
}

compile() {
    cxx="$1"
    sources="$2"
    objects=""
    mkdir -p "$build_dir"
    for src in $sources; do
        obj="$build_dir/$(basename "$src" .cpp).o"
        if needs_build "$obj" "$src"; then
            # stdout carries the object list back to the caller, so the
            # compiler's own output has to go to stderr.
            # shellcheck disable=SC2086
            "$cxx" $flags -Isrc -c "$src" -o "$obj" >&2
        fi
        objects="$objects $obj"
    done
    printf '%s' "$objects"
}

clean() {
    rm -rf "$build_dir" "$out"
}

build_binary() {
    cxx="$(find_compiler)" || {
        echo "tab-goto: no C++ compiler found (set CXX)" >&2
        return 1
    }
    objects="$(compile "$cxx" "src/*.cpp")"
    mkdir -p "$build_dir"
    staged="$build_dir/$out.$$"
    # shellcheck disable=SC2086
    "$cxx" $flags -Isrc $(link_flags) $objects -o "$staged"
    # Move into place so a killed or concurrent build can never leave a
    # half-written binary behind.
    mv -f "$staged" "$out"
    echo "tab-goto: built $dir/$out"
}

case "${1:-build}" in
    build) build_binary ;;
    clean) clean ;;
    *)
        echo "usage: $0 [build|clean]" >&2
        exit 2
        ;;
esac
