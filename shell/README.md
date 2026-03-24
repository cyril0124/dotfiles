# Shell Load Flow

This directory contains the shared shell configuration used by both bash and zsh.

## Entry Points

- [`/nfs/home/zhengchuyu/dotfiles/.bashrc`](/nfs/home/zhengchuyu/dotfiles/.bashrc)
- [`/nfs/home/zhengchuyu/dotfiles/.zshrc`](/nfs/home/zhengchuyu/dotfiles/.zshrc)

`bootstrap shell` links these two files to `~/.bashrc` and `~/.zshrc`.

## Bash Load Order

When an interactive bash shell starts:

1. `~/.bashrc` runs the tracked repo entrypoint.
2. `.bashrc` resolves the real path of itself and sets `DOTFILES_SHELL_ROOT`.
3. `.bashrc` sources `shell/common.sh`.
4. `.bashrc` sources `shell/bash.sh`.
5. If present, `.bashrc` sources `shell/local/common.sh`.
6. If present, `.bashrc` sources `shell/local/bash.sh`.

Effective order:

```text
~/.bashrc
  -> dotfiles/.bashrc
  -> shell/common.sh
  -> shell/bash.sh
  -> shell/local/common.sh
  -> shell/local/bash.sh
```

## Zsh Load Order

When zsh starts:

1. `~/.zshrc` runs the tracked repo entrypoint.
2. `.zshrc` resolves the real path of itself and sets `DOTFILES_SHELL_ROOT`.
3. `.zshrc` sources `shell/common.sh`.
4. If present, `.zshrc` sources `shell/local/common.sh`.
5. If present, `.zshrc` sources `shell/local/zsh.sh`.
6. `.zshrc` sources `shell/zsh.sh`.
7. `shell/zsh.sh` ensures `zimfw` exists under `${ZDOTDIR:-$HOME}/.zim` and downloads it automatically when missing.
8. `shell/zsh.sh` uses the tracked [`zimrc`](/nfs/home/zhengchuyu/dotfiles/shell/zimrc) as `ZIM_CONFIG_FILE`, rebuilds `init.zsh` when needed, and sources `${ZIM_HOME}/init.zsh`.
9. `.zshrc` initializes `pixi` completion, `direnv`, and `starship` after local overlays are loaded.

Effective order:

```text
~/.zshrc
  -> dotfiles/.zshrc
  -> shell/common.sh
  -> shell/local/common.sh
  -> shell/local/zsh.sh
  -> shell/zsh.sh
  -> ${ZIM_HOME}/zimfw.zsh (auto-download if missing)
  -> ${ZIM_HOME}/init.zsh
  -> pixi completion
  -> direnv hook
  -> starship init
```

## File Responsibilities

- `common.sh`: shared aliases, helper functions, generic PATH helpers, and shell-agnostic defaults.
- `bash.sh`: bash-only behavior such as history options, completion, binds, and bash prompt integration.
- `zsh.sh`: zsh-only behavior such as `zimfw` bootstrap and zsh history options.
- `zimrc`: tracked `zimfw` module declarations loaded through `ZIM_CONFIG_FILE`.
- `local/common.sh`: ignored by git; shared secrets, proxies, license settings, machine-specific PATH entries, toolchains.
- `local/bash.sh`: ignored by git; bash-only local overrides.
- `local/zsh.sh`: ignored by git; zsh-only local overrides.

## Override Rules

- `shell/local/common.sh` and `shell/local/zsh.sh` load before zsh-specific hook setup, so machine-specific PATH entries are available to `pixi`, `direnv`, and `starship`.
- `common.sh` loads before shell-specific files, so shared helpers like `command_exists`, `path_prepend`, and `path_append` are available everywhere else.
- `common.sh`, `bash.sh`, and `zsh.sh` each use a guard variable to avoid duplicate loading inside one shell session.

## Practical Notes

- If a tool path is added in `shell/local/common.sh`, functions defined in `common.sh` still work because command availability checks happen at runtime.
- The local files are intentionally ignored by git:
  - `shell/local/common.sh`
  - `shell/local/bash.sh`
  - `shell/local/zsh.sh`
- Template files are tracked for reference:
  - `shell/local/common.example.sh`
  - `shell/local/bash.example.sh`
  - `shell/local/zsh.example.sh`
- Non-invasive validation is available via [`scripts/validate_shell_setup.sh`](/nfs/home/zhengchuyu/dotfiles/scripts/validate_shell_setup.sh). It uses temporary link targets and `ZDOTDIR`/`--rcfile`, so it does not modify your current `~/.bashrc` or `~/.zshrc`.
