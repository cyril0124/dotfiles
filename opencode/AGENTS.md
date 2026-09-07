# AGENTS.md

## Language

- Default to Chinese in user-facing replies unless the user explicitly requests another language.
- Code comments must be written in English only, unless the file already has a clear non-English convention.

## Response Style

- Do not propose follow-up tasks or enhancement at the end of your final answer.
- For abstract concepts, multi-layer relationships, multi-step flows, or comparisons, prefer using concise ASCII visual diagrams to aid understanding. For simple questions, answer directly in text without forcing a diagram.

## Tool Usage Principles

- Calls that are parallelizable, independent, free of shared writes, free of ordering dependencies, and cheaper to summarize than to serialize should be run in parallel.
- Calls with dependencies, shared state, result interference, or obviously higher noise and summarization cost when parallelized must be run sequentially.

## Engineering Quality Baseline

- Write human-readable, maintainable code: use descriptive names, straightforward control flow, and cohesive functions with clear responsibilities. Prefer clarity over cleverness or terse expressions.
- Keep code visually clean and easy to scan through consistent formatting, logical grouping, and the project's existing conventions. Structure code so a reader can understand and safely change it without reconstructing hidden assumptions.

- Do not preserve backward compatibility. Remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, configuration, and indirection.
- Grow the system in layers. Start from the smallest version that works end to end, and add each new capability on top of a product that already works. Never trade a working product for unfinished complexity.
- Keep components modular and concerns clearly separated.
- Prefer established, well-maintained libraries when they reduce overall complexity or improve reliability. Do not reimplement common functionality without a clear reason.
- Lean on the dependencies already in the project before writing your own implementation or adding packages. Do not assume a library lacks a capability without checking its documentation and types.
- Make architectural decisions for the long term. Do not accept a stopgap that only works for now and is meant to be replaced later.

## Reality Over Assumption

- **IMPORTANT:** Reality is the only authority. If code, tests, logs, or runtime behavior contradict your assumption, your assumption is wrong.
- Never present guesses, plausibility, or code inspection alone as evidence that something works.
- If something cannot be verified within the current task, state that explicitly instead of implying confidence.

## Testing and Validation

- Keep code testable. Prioritize end-to-end tests that exercise real user workflows across integrated components and assert meaningful observable outcomes. Use focused unit tests only where they cover concrete risks more effectively, such as complex logic or hard-to-reach edge cases. Scale coverage to behavioral risk rather than test count.
- Do not over-test. Skip dedicated tests for trivial, deterministic facts whose correctness is already clear, such as asserting that a fixed string exists in a file. Add tests when they reduce a concrete regression risk or resolve behavioral uncertainty.
- Avoid tests that add no meaningful coverage, including getter/setter snapshots, mock-only assertions, implementation-detail checks, and no-risk happy paths.
- When running backend unit tests, enforce a hard timeout of 60 seconds to avoid stuck tasks.
- Prefer static checks, formatting, and reproducible verification over ad-hoc manual confidence.

## Execution Principles

- Fill in missing information: when the user's intent is incomplete, first gather what can be directly obtained from the code, files, configuration, and context. Do not guess, and do not ask the user for information that can be retrieved directly.
- Do not run `git reset --hard` or `git push` unless the user explicitly asks for it.
- Before finishing the task, clean up any temporary files and scripts created during this task. If they are needed for reproduction, troubleshooting, or the user explicitly asks to keep them, keep them and say so.
- Think before coding: state assumptions explicitly; if multiple interpretations exist, present them instead of picking silently; push back when a simpler approach exists; stop and ask when confused.
