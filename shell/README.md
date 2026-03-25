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
7. `.bashrc` initializes `direnv` and `starship` after local overlays are loaded.
Effective order:

```text
~/.bashrc
  -> dotfiles/.bashrc
  -> shell/common.sh
  -> shell/bash.sh
  -> shell/local/common.sh
  -> shell/local/bash.sh
  -> direnv hook
  -> starship init
```

## Zsh Load Order

When zsh starts:

1. `~/.zshrc` runs the tracked repo entrypoint.
2. `.zshrc` resolves the real path of itself and sets `DOTFILES_SHELL_ROOT`.
3. `.zshrc` sources `shell/common.sh`.
4. If present, `.zshrc` sources `shell/local/common.sh`.
5. If present, `.zshrc` sources `shell/local/zsh.sh`.
6. `.zshrc` sources `shell/zsh.sh`.
7. `shell/zsh.sh` ensures `oh-my-zsh` exists under `${ZDOTDIR:-$HOME}/.oh-my-zsh` and clones it automatically when missing.
8. `shell/zsh.sh` ensures the required custom plugins exist under `${ZSH_CUSTOM}/plugins` and then sources `${ZSH}/oh-my-zsh.sh`.
9. `.zshrc` initializes `pixi` completion, `direnv`, and `starship` after local overlays are loaded.

Effective order:

```text
~/.zshrc
  -> dotfiles/.zshrc
  -> shell/common.sh
  -> shell/local/common.sh
  -> shell/local/zsh.sh
  -> shell/zsh.sh
  -> ${ZSH}/oh-my-zsh.sh (auto-clone if missing)
  -> ${ZSH_CUSTOM}/plugins/* (auto-clone if missing)
  -> pixi completion
  -> direnv hook
  -> starship init
```

## File Responsibilities

- `common.sh`: shared aliases, helper functions, generic PATH helpers, and shell-agnostic defaults.
- `bash.sh`: bash-only behavior such as history options, completion, binds, and the `fzf`-powered `Ctrl-R` history picker.
- `zsh.sh`: zsh-only behavior such as `oh-my-zsh` bootstrap, plugin bootstrap, zsh history options, and the `fzf`-powered `Ctrl-R` history picker.
- `starship.toml`: tracked shared Starship prompt theme used by both bash and zsh.
- `local/common.sh`: ignored by git; shared secrets, proxies, license settings, machine-specific PATH entries, toolchains.
- `local/bash.sh`: ignored by git; bash-only local overrides.
- `local/zsh.sh`: ignored by git; zsh-only local overrides.

## Override Rules

- `shell/local/common.sh` and `shell/local/zsh.sh` load before zsh-specific hook setup, so machine-specific PATH entries are available to `pixi`, `direnv`, `starship`, and `fzf`.
- `shell/local/zsh.sh` also loads before `oh-my-zsh`, so plugin-specific variables such as `ZSHZ_MAX_SCORE` can be set there.
- `.bashrc` also initializes `direnv` and `starship` after bash local overlays, so local PATH or shell variables can affect those integrations too.
- `common.sh` loads before shell-specific files, so shared helpers like `command_exists`, `path_prepend`, and `path_append` are available everywhere else.
- `common.sh` sets `STARSHIP_CONFIG` to the tracked `shell/starship.toml` unless you override it locally.
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
- `Ctrl-R` uses `fzf` history search in both bash and zsh when `fzf` is available.
- Non-invasive validation is available via [`scripts/validate_shell_setup.sh`](/nfs/home/zhengchuyu/dotfiles/scripts/validate_shell_setup.sh). It uses temporary link targets and `ZDOTDIR`/`--rcfile`, so it does not modify your current `~/.bashrc` or `~/.zshrc`.
