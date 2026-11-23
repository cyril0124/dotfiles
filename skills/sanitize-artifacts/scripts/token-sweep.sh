#!/usr/bin/env bash
# Scan current artifact versions for session tokens; report HEAD separately.
#
# usage: token-sweep.sh <artifact> [token ...]
#        token-sweep.sh <artifact> --tokens-file <path> [token ...]
#
# A tokens file holds one token per line. Surrounding whitespace is trimmed and
# blank lines are skipped; every other line is a token, so #1234 stays a token.
#
# exit 0: no current-version hits. exit 1: current hits. exit 2: input error.
#
# Every hit prints as: <source> <path>:<line>: [<token>] <content>
# Line numbers refer to each source's complete file content. HEAD hits are
# historical information and do not affect the exit code.

set -u

program_name=${0##*/}

usage() {
    cat >&2 <<EOF
usage: $program_name <artifact> [token ...]
       $program_name <artifact> --tokens-file <path> [token ...]

Scans <artifact> on disk and in the Git index. HEAD hits are informational.
Tokens are matched literally. exit 0 current versions clean, 1 hits, 2 input error.
EOF
}

artifact=""
tokens_file=""
tokens=()

while [ $# -gt 0 ]; do
    case "$1" in
        --tokens-file)
            if [ $# -lt 2 ]; then
                echo "$program_name: --tokens-file needs a path" >&2
                exit 2
            fi
            tokens_file=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ $# -gt 0 ]; do
                tokens+=("$1")
                shift
            done
            ;;
        -*)
            echo "$program_name: unknown option $1 (pass tokens after --)" >&2
            exit 2
            ;;
        *)
            if [ -z "$artifact" ]; then
                artifact=$1
            else
                tokens+=("$1")
            fi
            shift
            ;;
    esac
done

if [ -z "$artifact" ]; then
    usage
    exit 2
fi

if [ -n "$tokens_file" ]; then
    if [ ! -f "$tokens_file" ]; then
        echo "$program_name: no such tokens file: $tokens_file" >&2
        exit 2
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%"${line##*[![:space:]]}"}
        line=${line#"${line%%[![:space:]]*}"}
        [ -z "$line" ] && continue
        tokens+=("$line")
    done < "$tokens_file"
fi

if [ ${#tokens[@]} -eq 0 ]; then
    echo "$program_name: no tokens given" >&2
    usage
    exit 2
fi

workdir=$(mktemp -d) || exit 2
trap 'rm -rf "$workdir"' EXIT

# Each source is "<label> <path-in-artifact-fact> <snapshot-file>". A snapshot
# holds the exact text that source contributes, so grep line numbers line up
# with what gets printed.
sources=()

if [ -f "$artifact" ]; then
    cat "$artifact" > "$workdir/worktree.txt"
    sources+=("worktree|$artifact|$workdir/worktree.txt")
elif [ -d "$artifact" ]; then
    echo "$program_name: $artifact is a directory; pass one file" >&2
    exit 2
fi

repo=$(git -C "$(dirname "$artifact")" rev-parse --show-toplevel 2>/dev/null) || repo=""

if [ -n "$repo" ]; then
    absolute=$(cd "$(dirname "$artifact")" 2>/dev/null && pwd)/$(basename "$artifact")
    tracked_path=${absolute#"$repo"/}

    if git -C "$repo" cat-file -e "HEAD:$tracked_path" 2>/dev/null; then
        git -C "$repo" show "HEAD:$tracked_path" > "$workdir/head.txt" 2>/dev/null
        sources+=("HEAD|$tracked_path|$workdir/head.txt")
    fi

    if git -C "$repo" cat-file -e ":$tracked_path" 2>/dev/null; then
        git -C "$repo" show ":$tracked_path" > "$workdir/staged.txt" 2>/dev/null
        sources+=("staged|$tracked_path|$workdir/staged.txt")
    fi
fi

if [ ${#sources[@]} -eq 0 ]; then
    echo "$program_name: nothing to scan: $artifact does not exist and is not in git" >&2
    exit 2
fi

hits=0
historical_hits=0

for source in "${sources[@]}"; do
    label=${source%%|*}
    rest=${source#*|}
    path=${rest%%|*}
    snapshot=${rest#*|}

    for token in "${tokens[@]}"; do
        while IFS= read -r match; do
            printf '%s %s:%s [%s] %s\n' "$label" "$path" "${match%%:*}" "$token" "${match#*:}"
            if [ "$label" = "HEAD" ]; then
                historical_hits=$((historical_hits + 1))
            else
                hits=$((hits + 1))
            fi
        done < <(grep -nF -- "$token" "$snapshot")
    done
done

if [ "$historical_hits" -gt 0 ]; then
    echo "$program_name: $historical_hits historical HEAD hit(s) (informational)" >&2
fi

if [ "$hits" -gt 0 ]; then
    echo "$program_name: $hits current-version hit(s)" >&2
    exit 1
fi

echo "$program_name: current versions clean" >&2
exit 0
