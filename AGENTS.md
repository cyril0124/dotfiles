# AGENTS.md

## Commit Messages

- Always use the Conventional Commits 1.0.0 format for git commit messages.
- Follow the structure: `<type>[optional scope]: <description>`.
- Prefer concise lowercase types such as `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `perf`, and `build`.
- Use a scope when it improves clarity, for example: `feat(nvim): add quit lock menu toggle`.
- Mark breaking changes with `!` before the colon or with a `BREAKING CHANGE:` footer when needed.
- Reference: https://www.conventionalcommits.org/en/v1.0.0/

## Skills must be self-contained

- When writing or editing a reusable skill, put full behavior rules inside that skill.
- Do not define a skill's output or workflow by referencing another skill (e.g. "use X skill's format").
- Inline the required format, steps, and severity labels so the skill works without implied dependencies.
