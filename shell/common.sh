if [ -n "${DOTFILES_SHELL_COMMON_LOADED:-}" ]; then
    return 0
fi
DOTFILES_SHELL_COMMON_LOADED=1

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

path_prepend() {
    [ -n "${1:-}" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1${PATH:+:$PATH}" ;;
    esac
}

path_append() {
    [ -n "${1:-}" ] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="${PATH:+$PATH:}$1" ;;
    esac
}

export EDITOR="${EDITOR:-nvim}"
export RUST_BACKTRACE="${RUST_BACKTRACE:-1}"
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$DOTFILES_SHELL_ROOT/shell/starship.toml}"

if [ -z "${FZF_DEFAULT_OPTS:-}" ]; then
    export FZF_DEFAULT_OPTS="--reverse"
fi

export NIX_HOME="${NIX_HOME:-$HOME/.config/nixpkgs}"

if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

path_prepend "$HOME/.pixi/bin"
path_prepend "$HOME/.local/bin"

if command_exists npm; then
    dotfiles_npm_prefix="$(npm config get prefix 2>/dev/null)"
    if [ -n "$dotfiles_npm_prefix" ] && [ "$dotfiles_npm_prefix" != "undefined" ]; then
        path_append "$dotfiles_npm_prefix/bin"
    fi
    unset dotfiles_npm_prefix
fi

alias c='clear'
alias ..='cd ..'
alias ls='ls --color=tty'
alias gl='git log'
alias gs='git status'
alias p='python3'
alias v='$EDITOR'
alias hs='home-manager switch'
alias vz='$EDITOR ~/.zshrc'
alias vb='$EDITOR ~/.bashrc'
alias sb='source ~/.bashrc'
alias k9='kill -9'
alias knfs='kill -9 $(lsof -t .nfs*)'
alias pl='parallel'
alias vf='v $(fzf)'
alias rgn='rg --no-ignore --hidden'
alias t='tmux'
alias ta='tmux a'
alias tn='tmux new'
alias tdc='tmux detach-client -s'
alias op='opencode'

alias vi='nvim'
alias vim='nvim'
alias vimdiff='nvim -d'

fzf() {
    if [ -t 0 ]; then
        command fzf --preview 'bat --color=always {}' "$@"
        return
    fi

    command fzf "$@"
}

zf() {
    command_exists z || return 1
    command_exists fzf || return 1

    local dir
    dir="$(z -l | command fzf --ignore-case --height 40% --reverse --inline-info | awk '{print $2}')"
    [ -n "$dir" ] || return 0
    cd "$dir" || return
}

ka() {
    local stopped_jobs pid
    stopped_jobs="$(ps -o pid=,stat= | awk '$2 ~ /T/ { print $1 }')"

    if [ -z "$stopped_jobs" ]; then
        echo "[kill all] No jobs to kill."
        return 0
    fi

    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        echo "[kill all] Killing process $pid"
        if kill -9 "$pid" 2>/dev/null; then
            echo "[kill all] Successfully killed process $pid"
        else
            echo "[kill all] Failed to kill process $pid"
        fi
    done <<EOF
$stopped_jobs
EOF
}

lsofr() {
    local directory="$1"

    if [ -z "$directory" ]; then
        echo "[lsofr] Please enter a valid directory!"
        return 1
    fi

    find "$directory" -type f -exec lsof {} +
}

setup_proxy() {
    local quiet=0
    local default_http_proxy="http://127.0.0.1:7890"
    local http_proxy_value="${1:-$default_http_proxy}"

    if [ "${1:-}" = "--quiet" ] || [ "${1:-}" = "-q" ]; then
        quiet=1
        http_proxy_value="$default_http_proxy"
    elif [ "${2:-}" = "--quiet" ] || [ "${2:-}" = "-q" ]; then
        quiet=1
    fi

    if [ "$quiet" -ne 1 ]; then
        echo "[setup_proxy] $http_proxy_value"
    fi

    export http_proxy="$http_proxy_value"
    export https_proxy="$http_proxy_value"
    export ftp_proxy="$http_proxy_value"
    export HTTP_PROXY="$http_proxy_value"
    export HTTPS_PROXY="$http_proxy_value"
    export FTP_PROXY="$http_proxy_value"
}

unset_proxy() {
    echo "[unset_proxy] ${http_proxy:-}"

    unset http_proxy
    unset https_proxy
    unset ftp_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset FTP_PROXY
}
