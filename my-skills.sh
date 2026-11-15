#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SKILLS_RUNNER=(npx --yes skills)
SKILLS_TIMEOUT_SECONDS=${SKILLS_TIMEOUT_SECONDS:-120}
# Every update run clones the upstream repository behind the skills it checks,
# so updates get their own larger budget, timed per source group.
SKILLS_UPDATE_TIMEOUT_SECONDS=${SKILLS_UPDATE_TIMEOUT_SECONDS:-300}
AGENTS=(codex claude-code opencode)
declare -A INSTALLED_SKILLS=()
declare -A INSTALLED_SOURCES=()
LOCAL_SKILLS_ROOT="$SCRIPT_DIR/skills"
AGENTS_SKILLS_DIR="$HOME/.agents/skills"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
CODEX_SKILLS_DIR="$HOME/.codex/skills"
SKILL_LOCK_FILE="$HOME/.agents/.skill-lock.json"

LOCAL_SKILLS=(
  "generic-writing"
  "cyril-notes"
  "commit-stage"
  "grill-me"
  "update-agents-md"
  "cross-check"
  "review"
  "explain-diff"
  "show-diff"
  "minimal-change"
  "readable-code"
  "parallelize"
  "git-add-hunk"
  "self-improve"
  "handoff"
  "use-skill"
  "plain-speak"
  "ascii-visual"
  "visual-comment"
  "with-evidence"
  "simple-plan"
  "show-mermaid"
  "show-mermaid-ascii"
  "drawio-svg"
  "clone-pr"
  "find-simplifications"
  "doc-standards"
  "sanitize-artifacts"
  "worktree-dev"
  "sync-feature"
  "xpra-web"
  "explain-by-questions"
)

REMOTE_SKILLS=(
  "vercel-labs/agent-browser@agent-browser"
  "vercel-labs/skills|find-skills@find-skills"
  "kepano/obsidian-skills|obsidian-markdown@obsidian-markdown"
  "https://github.com/baidu-netdisk/bdpan-storage|baidu-drive@baidu-drive"
  "alchaincyf/darwin-skill@darwin-skill"
  "mattpocock/skills|writing-for-agents@writing-for-agents"
  "mattpocock/skills|teach@teach"
  "mattpocock/skills|retro@retro"
  "mattpocock/skills|grilling@grilling"
  "https://github.com/herdrdev/herdr|herdr@herdr"
  "seyedehsanhadi/sloptrim@sloptrim"
)

info() {
  printf '==> %s\n' "$1"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

show_help() {
  cat <<EOF
Usage: ./my-skills.sh [all|local|update|list]

Install the skills recorded in this repo.

Commands:
  all     Install all recorded skills (default)
  local   Install local repo skills only
  update  Update installed remote skills to their latest upstream versions
  list    Print the configured remote skills
  help    Show this message

Environment:
  SKILLS_TIMEOUT_SECONDS         Per skills CLI command timeout (default: 120)
  SKILLS_UPDATE_TIMEOUT_SECONDS  Per source-group update timeout (default: 300)
EOF
}

require_tools() {
  command -v npx >/dev/null 2>&1 || fail "npx is required to install skills"
}

run_skills_with_timeout() {
  local timeout_seconds=$1
  shift

  local timeout_cmd=()
  local status

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout "${timeout_seconds}s")
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd=(gtimeout "${timeout_seconds}s")
  fi

  if "${timeout_cmd[@]}" "${SKILLS_RUNNER[@]}" "$@"; then
    return 0
  else
    status=$?
  fi

  if [ "$status" -eq 124 ]; then
    printf 'ERROR: skills command timed out after %ss: skills %s\n' "$timeout_seconds" "$*" >&2
  fi

  return "$status"
}

run_skills() {
  run_skills_with_timeout "$SKILLS_TIMEOUT_SECONDS" "$@"
}

spec_skill_name() {
  printf '%s\n' "${1##*@}"
}

spec_source() {
  local spec_without_name=${1%@*}
  printf '%s\n' "${spec_without_name%%|*}"
}

spec_skill_selector() {
  local spec_without_name=${1%@*}

  if [ "$spec_without_name" = "${spec_without_name%%|*}" ]; then
    return 1
  fi

  printf '%s\n' "${spec_without_name#*|}"
}

installed_skill_names() {
  run_skills ls -g --json | python3 -c '
import json
import sys

for item in json.load(sys.stdin):
    name = item.get("name")
    if name:
        print(name)
'
}

load_installed_skills() {
  local installed_name
  INSTALLED_SKILLS=()
  while IFS= read -r installed_name; do
    [ -n "$installed_name" ] || continue
    INSTALLED_SKILLS["$installed_name"]=1
  done < <(installed_skill_names)
}

lock_skill_sources() {
  python3 - "$SKILL_LOCK_FILE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1]) as handle:
        lock = json.load(handle)
except (OSError, ValueError):
    sys.exit(1)

for name, entry in lock.get("skills", {}).items():
    print("{}\t{}".format(name, entry.get("source") or name))
PY
}

# update groups skills by upstream source, so the authoritative installed set is
# the lock file the CLI itself updates from. Reading it avoids a full scan of
# every agent directory.
load_installed_sources() {
  local name source lock_entries
  INSTALLED_SOURCES=()

  if lock_entries=$(lock_skill_sources); then
    while IFS=$'\t' read -r name source; do
      [ -n "$name" ] || continue
      INSTALLED_SOURCES["$name"]=$source
    done <<< "$lock_entries"
    return 0
  fi

  # Without the lock file the source of each skill is unknown, so every skill
  # becomes its own group.
  load_installed_skills
  for name in "${!INSTALLED_SKILLS[@]}"; do
    INSTALLED_SOURCES["$name"]=$name
  done
}

run_skills_add() {
  # -g installs into the user-level skill scope so bootstrap can restore the same
  # global environment on a fresh machine instead of tying skills to one repo.
  # -a targets the agent integrations we actually use, keeping installation
  # explicit instead of relying on the CLI's default agent selection behavior.
  # -y keeps bootstrap non-interactive, which matters for unattended setup.
  # DISABLE_TELEMETRY=1 avoids emitting telemetry during dotfiles bootstrap.
  DISABLE_TELEMETRY=1 run_skills add "$@" -g -a "${AGENTS[@]}" -y
}

run_skills_remove() {
  DISABLE_TELEMETRY=1 run_skills remove "$@" -g -a "${AGENTS[@]}" -y
}

run_skills_update() {
  # The update subcommand only handles scope and confirmation flags, so agent
  # targeting stays in the add/remove path and updated skills refresh in place.
  DISABLE_TELEMETRY=1 run_skills_with_timeout "$SKILLS_UPDATE_TIMEOUT_SECONDS" update "$@" -g -y
}

run_skills_add_for_spec() {
  local spec=$1
  local source selector

  source=$(spec_source "$spec")
  if selector=$(spec_skill_selector "$spec"); then
    run_skills_add "$source" --skill "$selector"
    return
  fi

  run_skills_add "$source"
}

install_local_skills() {
  local skill_name skill_path agents_target claude_target codex_target

  [ -d "$LOCAL_SKILLS_ROOT" ] || fail "local skills directory not found: $LOCAL_SKILLS_ROOT"

  info "installing local skills (symlink)"

  for skill_name in "${LOCAL_SKILLS[@]}"; do
    skill_path="$LOCAL_SKILLS_ROOT/$skill_name"
    [ -d "$skill_path" ] || fail "local skill not found: $skill_path"

    agents_target="$AGENTS_SKILLS_DIR/$skill_name"
    claude_target="$CLAUDE_SKILLS_DIR/$skill_name"
    codex_target="$CODEX_SKILLS_DIR/$skill_name"

    if [ -L "$agents_target" ]; then
      info "refresh local skill symlink: $skill_name"
      rm "$agents_target"
    elif [ -e "$agents_target" ]; then
      info "replace local skill copy with symlink: $skill_name"
      run_skills_remove "$skill_name"
      rm -rf "$agents_target"
    fi

    mkdir -p "$AGENTS_SKILLS_DIR"
    info "local: $skill_path → $agents_target"
    ln -s "$skill_path" "$agents_target"

    if [ -L "$claude_target" ]; then
      rm "$claude_target"
    elif [ -e "$claude_target" ]; then
      rm -rf "$claude_target"
    fi
    mkdir -p "$CLAUDE_SKILLS_DIR"
    ln -s "../../.agents/skills/$skill_name" "$claude_target"

    if [ -L "$codex_target" ]; then
      rm "$codex_target"
    elif [ -e "$codex_target" ]; then
      rm -rf "$codex_target"
    fi
    mkdir -p "$CODEX_SKILLS_DIR"
    ln -s "../../.agents/skills/$skill_name" "$codex_target"
  done
}

install_remote_skills() {
  info "installing remote skills"
  load_installed_skills

  local spec skill_name
  for spec in "${REMOTE_SKILLS[@]}"; do
    skill_name=$(spec_skill_name "$spec")
    if [ -n "${INSTALLED_SKILLS[$skill_name]:-}" ]; then
      info "skip add for installed skill: $skill_name"
      continue
    fi

    info "remote: $spec"
    run_skills_add_for_spec "$spec"
  done
}

update_remote_skills() {
  info "updating remote skills"
  load_installed_sources

  declare -A skills_by_source=()
  # Associative arrays keep no insertion order, so the update order is tracked
  # next to them.
  local source_order=()
  local spec skill_name source skill_names

  for spec in "${REMOTE_SKILLS[@]}"; do
    skill_name=$(spec_skill_name "$spec")
    source=${INSTALLED_SOURCES[$skill_name]:-}
    if [ -z "$source" ]; then
      info "skip update (not installed): $skill_name"
      continue
    fi

    if [ -z "${skills_by_source[$source]:-}" ]; then
      source_order+=("$source")
      skills_by_source["$source"]=$skill_name
    else
      skills_by_source["$source"]="${skills_by_source[$source]} $skill_name"
    fi
  done

  if [ "${#source_order[@]}" -eq 0 ]; then
    info "no installed remote skills to update"
    return
  fi

  local index=0 failed=()
  for source in "${source_order[@]}"; do
    index=$((index + 1))
    read -r -a skill_names <<< "${skills_by_source[$source]}"
    info "update ${index}/${#source_order[@]}: ${skill_names[*]} (source: $source)"
    if ! run_skills_update "${skill_names[@]}"; then
      failed+=("$source")
    fi
  done

  if [ "${#failed[@]}" -gt 0 ]; then
    fail "update failed for ${#failed[@]}/${#source_order[@]} sources: ${failed[*]}"
  fi

  info "updated ${#source_order[@]} sources"
}

print_list() {
  printf 'Local skills:\n'
  printf '  %s\n' "${LOCAL_SKILLS[@]}"
  printf 'Remote skills:\n'
  printf '  %s\n' "${REMOTE_SKILLS[@]}"
}

main() {
  local command=${1:-all}

  case "$command" in
    -h|--help|help)
      show_help
      ;;
    list)
      print_list
      ;;
    local)
      require_tools
      install_local_skills
      ;;
    all)
      require_tools
      install_remote_skills
      install_local_skills
      ;;
    update|upgrade)
      require_tools
      update_remote_skills
      ;;
    *)
      show_help
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
