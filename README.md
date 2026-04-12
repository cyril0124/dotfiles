# Dotfiles

Personal configuration files for nvim, tmux, shell, pixi, opencode, claude, and codex.

## Installation

### Full Installation

Clone and run the bootstrap script:

```bash
git clone https://github.com/zhengchuyu/dotfiles.git ~/dotfiles
cd ~/dotfiles
./bootstrap
```

The bootstrap script will:
- Link config files from `config/` to `~/.config/`
- Back up and link `~/.bashrc` and `~/.zshrc`
- Install and configure pixi (if needed)
- Install tmux configuration
- Install and configure opencode (if needed)
- Configure claude settings
- Configure codex settings
- Install the skills recorded in `./my-skills.sh`

### Install Specific Components

You can also install only specific components:

```bash
./bootstrap [component ...]
```

Available components:
- `dotfiles` - Application configs (nvim, wezterm)
- `shell` - Bash and Zsh rc files with local overlay support
- `pixi` - Pixi package manager and global packages
- `tmux_conf` - Tmux configuration
- `opencode` - OpenCode AI configuration
- `claude` - Claude Code configuration
- `codex` - Codex configuration (`~/.codex`)
- `skills` - Install remote skills via `./my-skills.sh`
- `codex_sync` - Sync and sanitize local Codex config into this repo

Examples:
```bash
./bootstrap claude           # Install only claude config
./bootstrap codex            # Install only codex config
./bootstrap skills           # Install skills only
./bootstrap codex_sync       # Sync ~/.codex -> repo/codex (sanitized)
./bootstrap dotfiles claude  # Install multiple components
./my-skills.sh               # Install all recorded skills
./my-skills.sh list          # Show the recorded skills
```

## Structure

```
dotfiles/
├── .bashrc          # Bash entrypoint
├── .zshrc           # Zsh entrypoint
├── config/          # Application configs
│   ├── nvim/        # Neovim configuration
│   ├── wezterm/     # WezTerm terminal config
├── shell/           # Shared shell logic and local overlay templates
├── my-skills.sh     # Single entrypoint for skill installation
├── tmux/            # Tmux configuration (gpakosz/.tmux)
├── pixi/            # Pixi global packages
├── opencode/        # OpenCode AI configuration
├── claude/          # Claude Code configuration
└── codex/           # Codex configuration
```

## Components

### Neovim (config/nvim/)
Full-featured Neovim configuration with LSP, treesitter, and various plugins.

### Tmux (tmux/)
Uses [gpakosz/.tmux](https://github.com/gpakosz/.tmux) with custom local overrides in `.tmux.conf.local`.

### Shell (`.bashrc`, `.zshrc`, `shell/`)
- `.bashrc` and `.zshrc` are tracked entrypoints linked into `$HOME`
- Shared logic lives in `shell/common.sh`
- Shell-specific logic lives in `shell/bash.sh` and `shell/zsh.sh`
- Shared Starship theme lives in `shell/starship.toml`
- Zsh is managed by `oh-my-zsh`, and `shell/zsh.sh` auto-installs it and the required plugins when missing
- Load order and override rules are documented in [`shell/README.md`](/nfs/home/zhengchuyu/dotfiles/shell/README.md)
- Sensitive or machine-specific configuration should go into ignored local overlays:
  - `shell/local/common.sh`
  - `shell/local/bash.sh`
  - `shell/local/zsh.sh`
- Example overlay files are tracked as `*.example.sh`
- `bootstrap shell` backs up existing `~/.bashrc` and `~/.zshrc` before linking the tracked versions

### Pixi (pixi/)
- Pixi global package manifest for system-wide tools
- Auto-installs pixi if not present

### OpenCode (opencode/)
OpenCode AI configuration including:
- `opencode.jsonc` - Main configuration
- `oh-my-opencode.json` - Theme/settings
- `agents/` - Agent configurations

### Claude (claude/)
Claude Code configuration:
- `CLAUDE.md` - Global instructions for all projects
- `commands/` - Custom slash commands
- `plugins/` - Claude plugins

### Codex (codex/)
Codex configuration and prompt files:
- `config.toml` - Codex user configuration (sanitized; excludes machine-specific absolute-path `[projects."..."]` trust blocks and `[[skills.config]]` entries)
- `prompts/` - Custom prompts
- `codex_sync` will sync from `~/.codex` and sanitize machine-specific project entries and skill path entries with `scripts/sanitize_codex_config.py`

## Skills

`my-skills.sh` is the single place where remote skill installation is declared.

- Remote skills are recorded directly in `my-skills.sh` as `npx skills add ...` specs
- Installed global skill directories such as `~/.agents/skills` and `~/.claude/skills` are not synced back into this repo

## Requirements

- Bash or Zsh
- Git
- curl (for installing dependencies)
