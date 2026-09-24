# AGENTS.md

## Language

- Default to Chinese in user-facing replies unless the user explicitly requests another language.
- Code comments must be written in English only, unless the file already has a clear non-English convention.

## Response Style

- Do not propose follow-up tasks or enhancement at the end of your final answer.
- For abstract concepts, multi-layer relationships, multi-step flows, or comparisons, prefer using concise ASCII visual diagrams to aid understanding. For simple questions, answer directly in text without forcing a diagram.

## Tool Usage Principles

- Issue independent tool calls in parallel within the same response, e.g. several `bash` commands, `read` on multiple known files, or `rg`/`fd` probes that narrow the same search. A call that needs another call's output, or whose output would be excessive on its own, stays sequential.

## Engineering Quality Baseline

- Follow existing conventions and keep code readable, with descriptive names, straightforward control flow, and cohesive modules.
- Choose the simplest complete solution within the requested scope. For larger changes, keep each increment working end to end. Add abstractions only for current requirements.
- Check existing dependencies before implementing common functionality or adding packages. Prefer maintained libraries when they reduce total complexity.
- Within the requested change, remove obsolete internal paths rather than adding compatibility layers. Preserve persisted data and externally consumed interfaces unless the task explicitly authorizes breaking them.

## Reality Over Assumption

- **IMPORTANT:** Reality is the only authority. If code, tests, logs, or runtime behavior contradict your assumption, your assumption is wrong.
- Never present guesses, plausibility, or code inspection alone as evidence that something works.
- If something cannot be verified within the current task, state that explicitly instead of implying confidence.

## Testing and Validation

### Test Strategy

- Never write unit tests after the code. Tests written against a finished implementation only restate it, bugs included, and give false confidence.
- Highly prefer E2E as the sole testing mechanism: verify complex features work, not that individual functions return expected values.
- Pick a medium-to-hard E2E scenario, not the simplest that could pass: realistic input sizes, non-trivial state, real ordering or timing constraints, so a broken feature actually fails the test. Trivial happy path proves nothing.
- Every E2E run must produce a verifiable, repeatable artifact (report, log, screenshot, data file), re-checkable later without re-reading test code.
- Testing a system in isolation: first list every way it could fail, then write the code.

### Validation Scope

- Choose validation proportional to behavioral risk. Prefer checks that verify observable outcomes; add tests for concrete regression risks.
- After relevant checks pass, stop testing unless new changes or evidence justify more. Use explicit timeouts suited to the command; investigate timeouts instead of blindly rerunning.

## Execution Principles

- Fill in missing information: when the user's intent is incomplete, first gather what can be directly obtained from the code, files, configuration, and context. Do not guess, and do not ask the user for information that can be retrieved directly.
- Do not run `git reset --hard` or `git push` unless the user explicitly asks for it.
- Before finishing the task, clean up any temporary files and scripts created during this task. If they are needed for reproduction, troubleshooting, or the user explicitly asks to keep them, keep them and say so.
- Resolve routine implementation choices using repository evidence and existing conventions. Ask only when missing information materially changes scope, user-visible behavior, or safety.
- For implementation tasks, continue through implementation, relevant validation, and fixing failures caused by the change. Stop when the requested outcome is verified or a concrete blocker requires user input. Stay within the requested scope.
