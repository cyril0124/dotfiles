---
name: simple-plan
description: Write implementation plans before coding. Use when the user asks for a plan, implementation steps, delivery plan, plan-before-coding, or revise/run/run-verify controls. Produces scoped assumptions, dependency-ordered steps, checklist, and a confirmation line.
---

# Simple Plan

Turn available context into a clear, executable implementation plan for the next implementation pass.

## Workflow

1. Identify the goal and intended outcome from the latest user request.
2. Inspect only the context needed to know current state, constraints, and likely touch points.
3. Separate hard constraints from narrow assumptions. Name missing facts instead of inventing them.
4. Choose the smallest sufficient path: existing pattern -> standard library/native feature -> installed dependency -> minimal new code.
5. Explain the implementation approach, show it as a concise ASCII visual, add a one-sentence plain-language summary, then decompose it into dependency-ordered steps; give each step a verification target.
6. List only visible, relevant skills from the current session's available skills list.
7. End with the exact confirmation line unless the latest request already selects `revise`, `run`, `run-verify`, or asks for no confirmation.

## Output Format

```markdown
## Plan

### Goal
<One paragraph with the goal and intended outcome.>

### Implementation Approach
<A concise explanation of how the implementation will achieve the goal.>

```text
<ASCII visual of the approach: flow, layers, or touch points.>
```

In one sentence: <State the core solution in short, plain language.>

### Assumptions
- <None, or narrow assumptions used to complete the plan.>

### Scope
- In: <included work>
- Out: <excluded work>

### Dependencies / Risks
- <None, or items that affect sequencing or correctness.>

### Suggested Skills
- <None, or visible skill + one-line reason.>

### Implementation Steps
1. <Action> in <file/module/area> -> verify: <check>.

### Checklist
- [ ] <Concrete item that must be true after implementation.>

Confirm: proceed? (revise / run / run-verify)
```

## Output Rules

- Match the user's language for all user-facing plan output.
- Use the section order shown above.
- Under `Implementation Approach`, include a short ASCII visual (fenced `text` block) that shows the approach at a glance.
- Use `None` when a section has no content.
- Start each implementation step with an action verb.
- Keep `Dependencies / Risks` to items that change sequencing, correctness, data safety, security, or verification.
- Make `Checklist` concrete enough to verify implementation completion.
- Omit discussion history, rejected alternatives, roadmap items, and speculative future work.
- Do not write code, edit files, or run implementation commands while producing the initial plan.
- End with `Confirm: proceed? (revise / run / run-verify)` unless the latest request selected an action or asked for no confirmation.

## CHECKPOINT

STOP before implementation after printing the plan. Continue only when the latest request contains:

- `revise`: incorporate changes and reprint the complete plan.
- `run`: implement the latest complete plan.
- `run-verify`: implement, then verify with an independent subagent.
- No-confirmation wording: omit the confirmation line; implement only if the request also authorizes implementation.

## Run Option

1. Implement the latest complete plan directly when it fits one agent thread.
2. For large plans, split work into independent subagent tasks by file, subsystem, or checklist slice.
3. Give each implementation subagent its scope, relevant steps, and checklist items.
4. Keep the main agent responsible for integration, conflicts, and final checklist coverage.
5. Report what changed and which checklist items passed.

## Run-Verify Option

1. Complete the run option first.
2. Copy the plan's `Checklist` verbatim into the verification subagent prompt.
3. Ask the subagent to inspect the real diff and relevant files against that `Checklist`.
4. Report pass/fail with checklist evidence.
5. If verification fails, fix only failed checklist items, launch a fresh independent verification subagent with the same `Checklist`, and repeat until the subagent reports no issues or a real blocker prevents completion.
6. If no verifier can run, report verification unavailable and do not claim checklist pass.

## Failure Handling

| Trigger | Action |
|---|---|
| No latest complete plan exists for `run` or `run-verify` | Print a plan first and stop at the checkpoint. |
| Required context is missing | List the missing fact under `Assumptions` or `Dependencies / Risks`; do not fabricate files, APIs, or commands. |
| Requested scope is too broad for one pass | Split into ordered phases; keep `Scope` explicit. |
| A step lacks a verification target | Rewrite that step before final output. |
| Verification fails | Fix only failed checklist items, then rerun independent verification until the subagent reports no issues or a real blocker prevents completion. |

## Anti-Patterns

Do not:

- Turn the plan into a design essay or product roadmap.
- Ask broad clarification questions before inspecting available local context.
- Recommend hidden or unavailable skills.
- Include speculative abstractions, new dependencies, or future-proofing not required by the goal.
- Treat assumptions as facts.
- Claim verification passed without a real check or verifier result.
- Continue implementing after the plan unless the latest request authorizes it.

## Boundary

Planning is complete when a capable agent can start work from the steps and checklist without rereading the conversation.
