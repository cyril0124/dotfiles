if [ -n "${DOTFILES_SHELL_ZSH_LOADED:-}" ]; then
    return 0
fi
DOTFILES_SHELL_ZSH_LOADED=1

export ZIM_HOME="${ZIM_HOME:-${ZDOTDIR:-$HOME}/.zim}"
export ZIM_CONFIG_FILE="${ZIM_CONFIG_FILE:-$DOTFILES_SHELL_ROOT/shell/zimrc}"

dotfiles_zimfw_file="$ZIM_HOME/zimfw.zsh"
dotfiles_zimfw_url="https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh"

if [ ! -s "$dotfiles_zimfw_file" ]; then
    mkdir -p "$ZIM_HOME"

    if command_exists curl; then
        command curl -fsSL "$dotfiles_zimfw_url" -o "$dotfiles_zimfw_file"
    elif command_exists wget; then
        command wget -q -O "$dotfiles_zimfw_file" "$dotfiles_zimfw_url"
    else
        print -u2 "dotfiles: neither curl nor wget is available; cannot install zimfw automatically."
    fi
fi

if [ -s "$dotfiles_zimfw_file" ]; then
    if [ ! -s "$ZIM_HOME/init.zsh" ] || [ "$ZIM_CONFIG_FILE" -nt "$ZIM_HOME/init.zsh" ] || [ "$dotfiles_zimfw_file" -nt "$ZIM_HOME/init.zsh" ]; then
        source "$dotfiles_zimfw_file" init -q
    fi

    if [ -s "$ZIM_HOME/init.zsh" ]; then
        source "$ZIM_HOME/init.zsh"
    fi
fi

if ! typeset -p _comps >/dev/null 2>&1; then
    autoload -U compinit && compinit -u
fi

setopt inc_append_history
setopt share_history
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_ignore_space

export HSTR_CONFIG=hicolor
export HISTCONTROL=ignorespace:ignoredups:erasedups
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=1000000
export SAVEHIST=1000000

alias sz='source ~/.zshrc'

precmd() {
    echo -n "\x1b]1337;CurrentDir=$(pwd)\x07"
}

unset dotfiles_zimfw_file
unset dotfiles_zimfw_url
