#!/bin/sh
# Launch a program inside an xpra session with a controlled working directory.
#
# xpra runs every child in the server's own cwd and offers no per-command cwd,
# so this wrapper moves to DIR first and then replaces itself with the program.
# exec keeps the pid xpra tracks, so `close` still finds the program by name.
#
# usage: xpra-run-in.sh DIR CMD [ARGS...]
[ "$#" -ge 2 ] || { echo "usage: xpra-run-in.sh DIR CMD [ARGS...]" >&2; exit 2; }
cd -- "$1" || exit 1
shift
exec "$@"
