#!/usr/bin/env bash

set -euo pipefail

SKILLS_RUNNER=(npx skills)
AGENTS=(codex claude-code opencode)
declare -A INSTALLED_SKILLS=()

REMOTE_SKILLS=(
  "vercel-labs/agent-browser@agent-browser"
  "vercel-labs/skills@find-skills"
  "anthropics/skills@docx"
  "anthropics/skills@frontend-design"
  "anthropics/skills@skill-creator"
  "github/awesome-copilot@refactor"
  "othmanadi/planning-with-files@planning-with-files"
  "lyndonkl/claude@socratic-teaching-scaffolds"
  "openai/skills@frontend-skill"
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
Usage: ./skills.sh [all|list]

Install the skills recorded in this repo.

Commands:
  all     Install all recorded skills (default)
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
    run_skills_add "$spec"
  done
}

print_list() {
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
    all)
      require_tools
      install_remote_skills
      ;;
    *)
      show_help
      fail "unknown command: $command"
      ;;
  esac
}

main "$@"
