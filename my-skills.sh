#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SKILLS_RUNNER=(npx skills)
AGENTS=(codex claude-code opencode)
 declare -A INSTALLED_SKILLS=()
 LOCAL_SKILLS_ROOT="$SCRIPT_DIR/skills"
 AGENTS_SKILLS_DIR="$HOME/.agents/skills"
 CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
 CODEX_SKILLS_DIR="$HOME/.codex/skills"

LOCAL_SKILLS=(
  "generic-writing"
  "cyril-notes"
  "commit-stage"
  "grill-me"
  "update-agents-md"
  "cross-check"
  "minimal-change"
  "parallelize"
  "git-add-hunk"
)

REMOTE_SKILLS=(
  "vercel-labs/agent-browser@agent-browser"
  "vercel-labs/skills@find-skills"
  "jeffallan/claude-skills@code-reviewer"
  "github/awesome-copilot@refactor"
  "lyndonkl/claude@socratic-teaching-scaffolds"
  "openai/skills@frontend-skill"
  "kepano/obsidian-skills@obsidian-markdown"
  "imxv/pretty-mermaid-skills@pretty-mermaid"
  "https://github.com/baidu-netdisk/bdpan-storage|baidu-drive@baidu-drive"
  "https://skills.sh/alchaincyf/darwin-skill/darwin-skill"
  "juliusbrussee/caveman@caveman"
  "juliusbrussee/caveman@compress"
  "juliusbrussee/caveman@caveman-review"
  "juliusbrussee/caveman@cavecrew"
  "mattpocock/skills@write-a-skill"
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
Usage: ./my-skills.sh [all|local|list]

Install the skills recorded in this repo.

Commands:
  all     Install all recorded skills (default)
  local   Install local repo skills only
  list    Print the configured remote skills
  help    Show this message
EOF
}

require_tools() {
  command -v npx >/dev/null 2>&1 || fail "npx is required to install skills"
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
  "${SKILLS_RUNNER[@]}" ls -g --json | python3 -c '
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

has_installed_remote_skills() {
  local spec
  for spec in "${REMOTE_SKILLS[@]}"; do
    if [ -n "${INSTALLED_SKILLS[$(spec_skill_name "$spec")]:-}" ]; then
      return 0
    fi
  done

  return 1
}

run_skills_update() {
  # The official CLI exposes update as a global operation, not a single-skill
  # operation. We therefore run it once when any declared skill is already
  # present, then follow with add to install missing skills and refresh agents.
  DISABLE_TELEMETRY=1 "${SKILLS_RUNNER[@]}" update
}

run_skills_add() {
  # -g installs into the user-level skill scope so bootstrap can restore the same
  # global environment on a fresh machine instead of tying skills to one repo.
  # -a targets the agent integrations we actually use, keeping installation
  # explicit instead of relying on the CLI's default agent selection behavior.
  # -y keeps bootstrap non-interactive, which matters for unattended setup.
  # DISABLE_TELEMETRY=1 avoids emitting telemetry during dotfiles bootstrap.
  DISABLE_TELEMETRY=1 "${SKILLS_RUNNER[@]}" add "$@" -g -a "${AGENTS[@]}" -y
}

run_skills_remove() {
  DISABLE_TELEMETRY=1 "${SKILLS_RUNNER[@]}" remove "$@" -g -a "${AGENTS[@]}" -y
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

  if has_installed_remote_skills; then
    info "updating already-installed skills"
    run_skills_update
  fi

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
    *)
      show_help
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
