if [ -n "${DOTFILES_SHELL_ZSH_LOADED:-}" ]; then
    return 0
fi
DOTFILES_SHELL_ZSH_LOADED=1

dotfiles_clone_git_repo() {
    [ -n "${1:-}" ] || return 1
    [ -n "${2:-}" ] || return 1

    if [ -d "$1/.git" ]; then
        return 0
    fi

    if [ -e "$1" ]; then
        print -u2 "dotfiles: $1 exists but is not a git checkout."
        return 1
    fi

    if ! command_exists git; then
        print -u2 "dotfiles: git is required to install oh-my-zsh automatically."
        return 1
    fi

    mkdir -p "${1:h}"
    if ! command git clone --depth 1 "$2" "$1" >/dev/null 2>&1; then
        print -u2 "dotfiles: failed to clone $2 into $1."
        return 1
    fi
}

export ZSH="${ZSH:-${ZDOTDIR:-$HOME}/.oh-my-zsh}"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
export ZSH_THEME=""

dotfiles_omz_bootstrap_failed=0

if [ ! -s "$ZSH/oh-my-zsh.sh" ]; then
    dotfiles_clone_git_repo "$ZSH" "https://github.com/ohmyzsh/ohmyzsh.git" || dotfiles_omz_bootstrap_failed=1
fi

if [ "$dotfiles_omz_bootstrap_failed" -eq 0 ]; then
    dotfiles_clone_git_repo "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git" || true
    dotfiles_clone_git_repo "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git" || true
fi

plugins=(
    git
    extract
    z
    vi-mode
    autojump
    zsh-autosuggestions
    zsh-syntax-highlighting
)

if [ -s "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
fi

alias gl='git log'

dotfiles_zsh_fzf_history_widget() {
    command_exists fzf || {
        zle reset-prompt
        return 0
    }

    setopt localoptions pipefail no_aliases noglobsubst noposixbuiltins no_glob 2>/dev/null

    local selected
    selected="$(
        fc -rl 1 2>/dev/null |
            awk '{ cmd=$0; sub(/^[[:space:]]*[0-9]+\**[[:space:]]+/, "", cmd); if (cmd != "" && !seen[cmd]++) print cmd }' |
            command fzf \
                --scheme=history \
                --height=40% \
                --layout=reverse \
                --border \
                --prompt='history> ' \
                --query "$LBUFFER"
    )" || {
        zle reset-prompt
        return 0
    }

    if [ -n "$selected" ]; then
        BUFFER="$selected"
        CURSOR=${#BUFFER}
    fi

    zle reset-prompt
}

zle -N dotfiles-fzf-history-widget dotfiles_zsh_fzf_history_widget
bindkey -M emacs '^R' dotfiles-fzf-history-widget
bindkey -M viins '^R' dotfiles-fzf-history-widget
bindkey -M vicmd '^R' dotfiles-fzf-history-widget

if ! typeset -p _comps >/dev/null 2>&1; then
    autoload -U compinit && compinit -u
fi

setopt inc_append_history
setopt share_history
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_ignore_space

export HISTCONTROL=ignorespace:ignoredups:erasedups
export HISTFILE="$HOME/.zsh_history"
export HISTSIZE=1000000
export SAVEHIST=1000000

alias sz='source ~/.zshrc'

precmd() {
    echo -n "\x1b]1337;CurrentDir=$(pwd)\x07"
}

unset dotfiles_omz_bootstrap_failed
unset -f dotfiles_clone_git_repo
