# AGENTS.md

## Language

- Default to Chinese in user-facing replies unless the user explicitly requests another language.
- Code comments must be written in English only, unless the file already has a clear non-English convention.

## Response Style

- Do not propose follow-up tasks or enhancement at the end of your final answer.
- For abstract concepts, multi-layer relationships, multi-step flows, or comparisons, prefer using concise ASCII visual diagrams to aid understanding. For simple questions, answer directly in text without forcing a diagram.

## Debug-First Policy (No Silent Fallbacks)

- Do **not** introduce new boundary rules / guardrails / blockers / caps (e.g. max-turns), fallback behaviors, or silent degradation **just to make it run**.
- Do **not** add mock/simulation fake success paths (e.g. returning `(mock) ok`, templated outputs that bypass real execution, or swallowing errors).
- Do **not** write defensive or fallback code; it does not solve the root problem and only increases debugging cost.
- Prefer **full exposure**: let failures surface clearly (explicit errors, exceptions, logs, failing tests) so bugs are visible and can be fixed at the root cause.
- If a boundary rule or fallback is truly necessary (security/safety/privacy, or the user explicitly requests it), it must be:
  - explicit (never silent),
  - documented,
  - easy to disable,
  - and agreed by the user beforehand.

## Tool Usage Principles

- Calls that are parallelizable, independent, free of shared writes, free of ordering dependencies, and cheaper to summarize than to serialize should be run in parallel.
- Calls with dependencies, shared state, result interference, or obviously higher noise and summarization cost when parallelized must be run sequentially.
- When necessary, use multiple parallel sub-agents to handle work that is decomposable and independent, and let the main agent perform the final aggregation and convergence. Do not split tasks that are tightly coupled, share too much context, or cost too much to merge.

### OpenCode-Specific Rules (OpenCode Only)

- In OpenCode, do not use `spawn_agent` by default. Parallel subtasks should be handled through multiple `task` calls within the same round so each subtask remains observable and resumable.
- Use `spawn_agent` only when the user explicitly requests it, or when the task is a one-off batch job that does not require per-subtask observability.

## Engineering Quality Baseline

- Follow SOLID, DRY, KISS, separation of concerns, and YAGNI.
- Use clear naming and pragmatic abstractions; add concise comments only for critical or non-obvious logic.
- Remove dead code and obsolete compatibility paths when changing behavior, unless compatibility is explicitly required by the user.
- Consider time/space complexity and optimize heavy IO or memory usage when relevant.
- Handle edge cases explicitly; do not hide failures.
- Keep changes small, incremental, and reversible. Prefer reusing existing abstractions, avoid duplication, and avoid unnecessary large refactors or whole-file rewrites.

## Testing and Validation

- Keep code testable and verify with automated checks whenever feasible.
- When running backend unit tests, enforce a hard timeout of 60 seconds to avoid stuck tasks.
- Prefer static checks, formatting, and reproducible verification over ad-hoc manual confidence.

## Execution Principles

- Think from first principles: identify the goal, constraints, and available paths first, then choose the most direct, lowest-cost, and verifiable solution. Reject habit-driven or path-dependent reasoning.
- Fill in missing information: when the user's intent is incomplete, first gather what can be directly obtained from the code, files, configuration, and context. Do not guess, and do not ask the user for information that can be retrieved directly.
- Before finishing the task, clean up any temporary files and scripts created during this task. If they are needed for reproduction, troubleshooting, or the user explicitly asks to keep them, keep them and say so.
