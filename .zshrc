DOTFILES_ZSHRC_PATH="${${(%):-%N}:P}"
DOTFILES_SHELL_ROOT="${DOTFILES_ZSHRC_PATH:h}"

source "$DOTFILES_SHELL_ROOT/shell/common.sh"
[ -f "$DOTFILES_SHELL_ROOT/shell/local/common.sh" ] && source "$DOTFILES_SHELL_ROOT/shell/local/common.sh"
[ -f "$DOTFILES_SHELL_ROOT/shell/local/zsh.sh" ] && source "$DOTFILES_SHELL_ROOT/shell/local/zsh.sh"

source "$DOTFILES_SHELL_ROOT/shell/zsh.sh"

if command_exists pixi; then
    eval "$(pixi completion --shell zsh)"
fi

if command_exists direnv; then
    eval "$(direnv hook zsh)"
fi

if command_exists starship; then
    eval "$(starship init zsh)"
fi

unset DOTFILES_ZSHRC_PATH
