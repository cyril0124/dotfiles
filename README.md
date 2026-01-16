# Dotfiles

Personal configuration files for nvim, tmux, pixi, opencode, and claude.

## Installation

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

## Structure

```
dotfiles/
├── config/          # Application configs (nvim, etc.)
├── tmux/            # Tmux configuration
├── pixi/            # Pixi global packages
├── opencode/        # OpenCode AI configuration
└── claude/          # Claude Code configuration
```

## Requirements

- Bash or Zsh
- Git
- curl (for installing dependencies)
