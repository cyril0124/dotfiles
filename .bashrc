case $- in
    *i*) ;;
    *) return ;;
esac

dotfiles_bashrc_source="${BASH_SOURCE[0]}"
while [ -L "$dotfiles_bashrc_source" ]; do
    dotfiles_bashrc_dir="$(cd -P -- "$(dirname -- "$dotfiles_bashrc_source")" && pwd)"
    dotfiles_bashrc_source="$(readlink -- "$dotfiles_bashrc_source")"
    case "$dotfiles_bashrc_source" in
        /*) ;;
        *) dotfiles_bashrc_source="$dotfiles_bashrc_dir/$dotfiles_bashrc_source" ;;
    esac
done
DOTFILES_SHELL_ROOT="$(cd -P -- "$(dirname -- "$dotfiles_bashrc_source")" && pwd)"
unset dotfiles_bashrc_dir
unset dotfiles_bashrc_source

. "$DOTFILES_SHELL_ROOT/shell/common.sh"
. "$DOTFILES_SHELL_ROOT/shell/bash.sh"

[ -f "$DOTFILES_SHELL_ROOT/shell/local/common.sh" ] && . "$DOTFILES_SHELL_ROOT/shell/local/common.sh"
[ -f "$DOTFILES_SHELL_ROOT/shell/local/bash.sh" ] && . "$DOTFILES_SHELL_ROOT/shell/local/bash.sh"
