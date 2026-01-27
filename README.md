# Dotfiles

Personal configuration files for nvim, tmux, pixi, opencode, claude, and iflow.

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
- Install and configure pixi (if needed)
- Install tmux configuration
- Install and configure opencode (if needed)
- Configure claude settings
- Configure iflow settings

### Install Specific Components

You can also install only specific components:

```bash
./bootstrap [component ...]
```

Available components:
- `dotfiles` - Application configs (nvim, wezterm, zellij)
- `pixi` - Pixi package manager and global packages
- `tmux_conf` - Tmux configuration
- `opencode` - OpenCode AI configuration
- `claude` - Claude Code configuration
- `iflow` - Iflow configuration

Examples:
```bash
./bootstrap claude           # Install only claude config
./bootstrap iflow            # Install only iflow config
./bootstrap dotfiles claude  # Install multiple components
```

## Structure

```
dotfiles/
├── config/          # Application configs
│   ├── nvim/        # Neovim configuration
│   ├── wezterm/     # WezTerm terminal config
│   └── zellij/      # Zellij multiplexer config
├── tmux/            # Tmux configuration (gpakosz/.tmux)
├── pixi/            # Pixi global packages
├── opencode/        # OpenCode AI configuration
├── claude/          # Claude Code configuration
└── iflow/           # Iflow configuration
```

## Components

### Neovim (config/nvim/)
Full-featured Neovim configuration with LSP, treesitter, and various plugins.

### Tmux (tmux/)
Uses [gpakosz/.tmux](https://github.com/gpakosz/.tmux) with custom local overrides in `.tmux.conf.local`.

### Pixi (pixi/)
- Pixi global package manifest for system-wide tools
- Auto-installs pixi if not present

### OpenCode (opencode/)
OpenCode AI configuration including:
- `opencode.jsonc` - Main configuration
- `oh-my-opencode.json` - Theme/settings
- `skill/` - Custom skills
- `agents/` - Agent configurations

### Claude (claude/)
Claude Code configuration:
- `CLAUDE.md` - Global instructions for all projects
- `commands/` - Custom slash commands
- `plugins/` - Claude plugins

### Iflow (iflow/)
Iflow configuration with symlinks to claude resources.

## Requirements

- Bash or Zsh
- Git
- curl (for installing dependencies)
