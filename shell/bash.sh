if [ -n "${DOTFILES_SHELL_BASH_LOADED:-}" ]; then
    return 0
fi
DOTFILES_SHELL_BASH_LOADED=1

HISTCONTROL=ignoreboth
HISTSIZE=100000
HISTFILESIZE=200000
shopt -s histappend
shopt -s checkwinsize
shopt -s globstar

if [ -x /usr/bin/lesspipe ]; then
    eval "$(SHELL=/bin/sh lesspipe)"
fi

if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

bind '"\e[A": history-search-backward'
bind '"\e[B": history-search-forward'

dotfiles_bash_fzf_history_widget() {
    command_exists fzf || return 0

    local selected
    selected="$(
        builtin fc -lnr 1 2>/dev/null |
            awk 'NF && !seen[$0]++' |
            command fzf \
                --scheme=history \
                --height=40% \
                --layout=reverse \
                --border \
                --prompt='history> ' \
                --query "$READLINE_LINE"
    )" || return

    [ -n "$selected" ] || return 0
    READLINE_LINE="$selected"
    READLINE_POINT=${#READLINE_LINE}
}

bind -x '"\C-r": dotfiles_bash_fzf_history_widget'

alias sb='source ~/.bashrc'
