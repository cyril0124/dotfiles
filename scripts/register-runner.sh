#!/usr/bin/env bash
set -euo pipefail
export GH_PAGER=""

RUNNER_VERSION="2.323.0"
_PAT_TOKEN=""

usage() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  register   Register and start a self-hosted runner
  run        Start an already registered runner
  cleanup    Remove all offline runners from the repo
  remove     Remove a specific runner
  list       List all runners registered on the repo

Register options:
  -r, --repo <owner/repo>    GitHub repository (required)
  -d, --dir <path>           Runner install directory (default: ~/actions-runner)
  -n, --name <name>          Runner name (default: \$(hostname))
  -l, --labels <labels>      Comma-separated labels (default: self-hosted,<name>)
  -t, --token <pat>          GitHub Classic PAT with repo+admin:org scopes

Run options:
  -d, --dir <path>           Runner install directory (default: ~/actions-runner)

Global options:
  -t, --token <pat>          GitHub Classic PAT (required if gh auth is OAuth)
  -h, --help                 Show this help message

Other commands (positional args):
  cleanup  <owner/repo>
  remove   <owner/repo> [runner-name]
  list     <owner/repo>

Examples:
  $(basename "$0") register -r myorg/myrepo
  $(basename "$0") register -r myorg/myrepo -n ci-runner
  $(basename "$0") register -r myorg/myrepo -d ~/runners/r1 -n r1 -l 'self-hosted,gpu,linux'
  $(basename "$0") run
  $(basename "$0") run -d ~/runners/r1
  $(basename "$0") cleanup myorg/myrepo
  $(basename "$0") remove myorg/myrepo
  $(basename "$0") list myorg/myrepo

Note:
  gh OAuth token (gho_*) does NOT support self-hosted runners API (returns 404).
  Fine-grained PAT also does NOT work for org repos (returns 403).
  You need a Classic PAT with 'repo' and 'admin:org' scopes:
    https://github.com/settings/tokens/new?scopes=repo,admin:org
  Then pass it with: -t ghp_xxx
EOF
}

gh_api_raw() {
    local method="${1:-GET}"
    local endpoint="$2"
    shift 2

    if [ -n "$_PAT_TOKEN" ]; then
        curl -sS -X "$method" \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $_PAT_TOKEN" \
            "https://api.github.com/${endpoint}" \
            "$@"
    else
        if [ "$method" = "GET" ]; then
            gh api "$endpoint" "$@"
        else
            gh api -X "$method" "$endpoint" "$@"
        fi
    fi
}

py_get() {
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$1',''))"
}

py_query() {
    python3 -c "
import json, sys
d = json.load(sys.stdin)
runners = d.get('runners', d)
if isinstance(runners, dict): runners = [runners]
for r in runners:
    name = r.get('name','')
    rid = r.get('id','')
    status = r.get('status','')
    os_name = r.get('os','')
    labels = ','.join(l.get('name','') for l in r.get('labels',[]))
    print(f'{rid}\t{name}\t{status}\t{os_name}\t{labels}')
"
}

py_find_id() {
    local name="$1"
    python3 -c "
import json, sys
d = json.load(sys.stdin)
runners = d.get('runners', d)
if isinstance(runners, dict): runners = [runners]
for r in runners:
    if r.get('name') == '$name':
        print(r.get('id',''))
        break
"
}

py_offline_ids() {
    python3 -c "
import json, sys
d = json.load(sys.stdin)
runners = d.get('runners', d)
if isinstance(runners, dict): runners = [runners]
for r in runners:
    if r.get('status') == 'offline':
        print(r.get('id',''))
"
}

require_auth() {
    if [ -n "$_PAT_TOKEN" ]; then
        return 0
    fi
    command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI not found. Install it or use --token."; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "Error: gh not authenticated. Run 'gh auth login' or use --token."; exit 1; }
}

api_base() {
    echo "repos/${1}/actions/runners"
}

list_runners() {
    local owner_repo="$1"
    if [ -n "$_PAT_TOKEN" ]; then
        local page=1
        local all=""
        while true; do
            local chunk
            chunk=$(curl -sS \
                -H "Accept: application/vnd.github+json" \
                -H "Authorization: Bearer $_PAT_TOKEN" \
                "https://api.github.com/$(api_base "$owner_repo")?per_page=100&page=$page" | py_query)
            [ -z "$chunk" ] && break
            all="${all:+$all$'\n'}$chunk"
            page=$((page + 1))
        done
        echo "$all"
    else
        gh api "$(api_base "$owner_repo")" --paginate -q '.runners[] | "\(.id)\t\(.name)\t\(.status)\t\(.os)\t\(.labels[].name)"' 2>/dev/null
    fi
}

cmd_list() {
    local owner_repo="${1:?Error: owner/repo required}"
    require_auth

    echo "==> Runners for ${owner_repo}:"
    echo "ID	Name	Status	OS	Labels"
    echo "---	----	------	--	------"
    local output
    output=$(list_runners "$owner_repo")
    if [ -z "$output" ]; then
        echo "(none)"
    else
        echo "$output" | column -t -s$'\t'
    fi
}

cmd_remove() {
    local owner_repo="${1:?Error: owner/repo required}"
    local runner_name="${2:-$(hostname)}"
    require_auth

    local runner_id
    if [ -n "$_PAT_TOKEN" ]; then
        runner_id=$(curl -sS \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $_PAT_TOKEN" \
            "https://api.github.com/$(api_base "$owner_repo")" | py_find_id "$runner_name")
    else
        runner_id=$(gh api "$(api_base "$owner_repo")" -q ".runners[] | select(.name==\"${runner_name}\") | .id" | head -1)
    fi

    if [ -z "$runner_id" ]; then
        echo "==> Runner '${runner_name}' not found on ${owner_repo}. Nothing to remove."
        return 0
    fi

    echo "==> Removing runner '${runner_name}' (id: ${runner_id}) from ${owner_repo}..."
    gh_api_raw DELETE "$(api_base "$owner_repo")/${runner_id}"
    echo "==> Done."
}

cmd_cleanup() {
    local owner_repo="${1:?Error: owner/repo required}"
    require_auth

    local offline_ids
    if [ -n "$_PAT_TOKEN" ]; then
        offline_ids=$(curl -sS \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $_PAT_TOKEN" \
            "https://api.github.com/$(api_base "$owner_repo")" | py_offline_ids)
    else
        offline_ids=$(gh api "$(api_base "$owner_repo")" -q '.runners[] | select(.status=="offline") | .id')
    fi

    if [ -z "$offline_ids" ]; then
        echo "==> No offline runners to clean up."
        return 0
    fi

    local count=0
    while IFS= read -r rid; do
        [ -z "$rid" ] && continue
        local rname
        rname=$(gh_api_raw GET "$(api_base "$owner_repo")/${rid}" | py_get 'name')
        echo "==> Removing offline runner '${rname}' (id: ${rid})"
        gh_api_raw DELETE "$(api_base "$owner_repo")/${rid}"
        count=$((count + 1))
    done <<< "$offline_ids"

    echo "==> Cleaned up ${count} offline runner(s)."
}

cmd_run() {
    local runner_dir=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -d|--dir) runner_dir="$2"; shift 2 ;;
            *) echo "Error: unknown option $1"; usage; exit 1 ;;
        esac
    done

    runner_dir="${runner_dir:-$HOME/actions-runner}"

    if [ ! -f "$runner_dir/run.sh" ]; then
        echo "Error: $runner_dir/run.sh not found. Is the runner installed here?"
        echo "  Use '$(basename "$0") register' to install first."
        exit 1
    fi

    cd "$runner_dir"
    echo "==> Starting runner in ${runner_dir}..."
    ./run.sh
}

get_field() {
    local endpoint="$1"
    local field="$2"
    if [ -n "$_PAT_TOKEN" ]; then
        curl -sS \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $_PAT_TOKEN" \
            "https://api.github.com/${endpoint}" | py_get "$field"
    else
        gh api "$endpoint" -q ".$field"
    fi
}

get_registration_token() {
    local owner_repo="$1"
    if [ -n "$_PAT_TOKEN" ]; then
        curl -sS -X POST \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $_PAT_TOKEN" \
            "https://api.github.com/$(api_base "$owner_repo")/registration-token" | py_get 'token'
    else
        gh api "$(api_base "$owner_repo")/registration-token" -q '.token'
    fi
}

find_runner_id() {
    local owner_repo="$1"
    local runner_name="$2"
    if [ -n "$_PAT_TOKEN" ]; then
        curl -sS \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $_PAT_TOKEN" \
            "https://api.github.com/$(api_base "$owner_repo")" | py_find_id "$runner_name"
    else
        gh api "$(api_base "$owner_repo")" -q ".runners[] | select(.name==\"${runner_name}\") | .id" | head -1
    fi
}

cmd_register() {
    local owner_repo="" runner_dir="" runner_name="" labels=""

    while [ $# -gt 0 ]; do
        case "$1" in
            -r|--repo)   owner_repo="$2"; shift 2 ;;
            -d|--dir)    runner_dir="$2"; shift 2 ;;
            -n|--name)   runner_name="$2"; shift 2 ;;
            -l|--labels) labels="$2"; shift 2 ;;
            -t|--token)  _PAT_TOKEN="$2"; shift 2 ;;
            *) echo "Error: unknown option $1"; usage; exit 1 ;;
        esac
    done

    if [ -z "$owner_repo" ]; then
        echo "Error: --repo is required."
        usage
        exit 1
    fi

    runner_dir="${runner_dir:-$HOME/actions-runner}"
    runner_name="${runner_name:-$(hostname)}"
    labels="${labels:-self-hosted,${runner_name}}"

    require_auth

    local existing_id
    existing_id=$(find_runner_id "$owner_repo" "$runner_name" || true)
    if [ -n "$existing_id" ]; then
        echo "==> Removing existing runner '${runner_name}' (id: ${existing_id})..."
        gh_api_raw DELETE "$(api_base "$owner_repo")/${existing_id}"
    fi

    if [ -f "$runner_dir/.runner" ]; then
        echo "==> Removing stale local runner config..."
        local remove_token
        remove_token=$(get_registration_token "$owner_repo")
        "$runner_dir/config.sh" remove --token "$remove_token" 2>/dev/null || true
    fi

    if [ ! -f "$runner_dir/config.sh" ]; then
        echo "==> Downloading runner v${RUNNER_VERSION} to ${runner_dir}..."
        mkdir -p "$runner_dir"
        local runner_os runner_arch
        runner_os=$(uname -s | tr '[:upper:]' '[:lower:]')
        runner_arch=$(uname -m)
        case "$runner_arch" in
            x86_64)  runner_arch="x64" ;;
            aarch64) runner_arch="arm64" ;;
            armv7l)  runner_arch="arm" ;;
            *) echo "Error: unsupported architecture $runner_arch"; exit 1 ;;
        esac
        local runner_tar="actions-runner-${runner_os}-${runner_arch}-${RUNNER_VERSION}.tar.gz"
        curl -L --progress-bar "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${runner_tar}" \
            | tar xz -C "$runner_dir"
    else
        echo "==> Runner already installed in ${runner_dir}, skipping download."
    fi

    cd "$runner_dir"

    echo "==> Fetching registration token for ${owner_repo}..."
    local token
    token=$(get_registration_token "$owner_repo")
    if [ -z "$token" ]; then
        echo "Error: failed to get registration token."
        echo "  gh OAuth token (gho_*) and Fine-grained PAT do not support runners API on org repos."
        echo "  You need a Classic PAT with 'repo' + 'admin:org' scopes:"
        echo "    https://github.com/settings/tokens/new?scopes=repo,admin:org"
        echo "  Then pass it with: -t ghp_xxx"
        exit 1
    fi

    echo "==> Configuring runner '${runner_name}' with labels: ${labels}"
    ./config.sh --unattended \
        --token "$token" \
        --url "https://github.com/${owner_repo}" \
        --name "$runner_name" \
        --labels "$labels"

    echo "==> Starting runner..."
    ./run.sh
}

parse_global_token() {
    if [ "${1:-}" = "-t" ] || [ "${1:-}" = "--token" ]; then
        _PAT_TOKEN="$2"
        shift 2
    fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

cmd="${1:-}"
shift || true

case "$cmd" in
    register) cmd_register "$@" ;;
    run)      cmd_run "$@" ;;
    cleanup)  parse_global_token "$@"; cmd_cleanup "$@" ;;
    remove)   parse_global_token "$@"; cmd_remove "$@" ;;
    list)     parse_global_token "$@"; cmd_list "$@" ;;
    *)        usage; exit 1 ;;
esac