# Prepare the draw.io CLI

Read this when draw.io Desktop is missing or its executable cannot export. The `drawio` CLI ships inside **draw.io Desktop**. Installing this skill, an MCP package, or a Python CLI wrapper does not install that binary.

## Choose the setup

1. Reuse an existing Desktop installation. Check `command -v drawio`, the platform's application directory, and any existing user-local installation before downloading again.
2. If missing, detect the OS and CPU architecture. Use an official [draw.io Desktop release](https://github.com/jgraph/drawio-desktop/releases) matching both. Prefer user-local installation when system packages or administrator access are unnecessary.
3. Use the Linux portable recipe below on compatible x86_64 systems, or the platform options in the table. A network failure or missing runtime library is a setup blocker to diagnose, not a reason to substitute a plain SVG.

| Platform | Setup |
| --- | --- |
| macOS with Homebrew | `brew install --cask drawio`. Resolve `drawio` on PATH or `/Applications/draw.io.app/Contents/MacOS/draw.io`. |
| Windows with winget | `winget install --exact --id JGraph.Draw`. Resolve the installed `draw.io.exe`; it may not be on PATH. |
| Windows without administrator access | Use the official per-user MSI or portable executable matching the CPU architecture. |
| Linux | Use an official `.deb`, `.rpm`, or AppImage matching the architecture. On compatible systems, extracting a `.deb` into a user-owned directory avoids package-manager changes. |

Use the resolved executable path in place of `drawio` in the main skill's commands. Quote paths containing spaces. In PowerShell, invoke a quoted executable path with `&`.

## Linux without sudo

The `.deb` extraction and headless export path was tested with Desktop **31.4.5 on Linux x86_64**. It needs `curl`, `dpkg-deb`, and compatible Electron runtime libraries. The version is explicit for reproducibility; reuse a working installation rather than upgrading it automatically. For another architecture or version, choose the matching asset from the official release instead of guessing a URL.

The recipe installs under `~/.local/share/drawio/<version>` and reuses it on later runs. It leaves shell startup files untouched. Run in Bash:

```bash
(
  set -eu
  drawio_version=31.4.5
  drawio_install_dir="$HOME/.local/share/drawio/$drawio_version"
  drawio_binary="$drawio_install_dir/opt/drawio/drawio"

  if [ ! -x "$drawio_binary" ]; then
    test "$(uname -s)" = Linux
    test "$(uname -m)" = x86_64
    command -v curl >/dev/null
    command -v dpkg-deb >/dev/null
    if [ -e "$drawio_install_dir" ]; then
      printf 'Incomplete installation at %s; inspect it before replacing it.\n' \
        "$drawio_install_dir" >&2
      exit 1
    fi

    mkdir -p "$(dirname "$drawio_install_dir")"
    drawio_stage="$(mktemp -d "$(dirname "$drawio_install_dir")/.install-XXXXXX")"
    trap 'rm -rf -- "$drawio_stage"' EXIT
    curl --fail --location --max-time 180 --retry 1 \
      --output "$drawio_stage/drawio.deb" \
      "https://github.com/jgraph/drawio-desktop/releases/download/v$drawio_version/drawio-amd64-$drawio_version.deb"
    dpkg-deb --extract "$drawio_stage/drawio.deb" "$drawio_stage/app"
    test -x "$drawio_stage/app/opt/drawio/drawio"
    mv "$drawio_stage/app" "$drawio_install_dir"
  fi

  printf 'draw.io executable: %s\n' "$drawio_binary"
)
```

This is a persistent dependency, not an intermediate diagram artifact. Keep it for future requests. If the user requested a temporary run instead, use a dedicated temporary directory and remove it after all validation completes.

Extraction does not install shared libraries. If the executable fails to start, inspect stderr and missing library dependencies. On Debian/Ubuntu, a system package installation can resolve dependencies with `sudo apt install ./<downloaded-package>.deb` when that operation is already authorized. Otherwise report the specific missing dependency or use an available editor export path. Do not add `--no-sandbox` as a generic fix.

## Headless startup and validation

On Linux without a working display, use `xvfb-run -a`. It needs both Xvfb and xauth; Debian/Ubuntu provide them through `sudo apt install xvfb xauth` when system package installation is authorized. If unavailable and privileges are missing, report that exact blocker.

An unrelated application's Xvfb can shadow the system binary. Check `type -a Xvfb` when startup fails. Where `/usr/bin/Xvfb` is the intended system installation, prefix the command with `env PATH="/usr/bin:/bin:$PATH"`.

For the Linux recipe above, check the CLI with a finite timeout:

```bash
timeout 30 env PATH="/usr/bin:/bin:$PATH" xvfb-run -a \
  "$HOME/.local/share/drawio/31.4.5/opt/drawio/drawio" --help
```

On a graphical desktop, call the resolved executable with `--help` directly, using the command runner's timeout if `timeout` is unavailable. Confirm that `--export`, `--format`, and `--embed-diagram` are supported. Check `--embed-svg-images` when the diagram needs embedded image assets.

A successful help command only verifies CLI startup. Before declaring the dependency ready, use the main skill's two-node XML example to export a fresh `.drawio.svg`, then run its bundled `scripts/verify_embedded.py` against that source. The PNG rendering and image-reading checks remain required for the requested diagram. Remove only the temporary smoke-test artifacts.

If download, startup, or export fails, include the attempted command, the relevant error, and the missing prerequisite. Resume the main workflow once the concrete failure is resolved.
