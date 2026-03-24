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

alias sb='source ~/.bashrc'
