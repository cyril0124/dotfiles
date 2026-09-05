---
name: simple-plan
description: Write complete, non-regressive implementation plans before coding. Use when the user asks for a plan, implementation steps, delivery plan, plan-before-coding, or revise/ask/run/run-verify controls. Produces full-goal coverage, preserved adjacent behavior, scoped assumptions, dependency-ordered steps, checklist, and a confirmation line.
---

# Simple Plan

Turn available context into an implementation plan the user can understand and correct before the AI executes it. Completeness of the requested goal comes first; lean implementation is chosen only among options that deliver the full goal without amputating adjacent capabilities.

## Completeness Rule

A plan is valid only if it satisfies all of the following:

1. **Full goal delivery** — every part of the requested outcome is covered by steps and checklist items. Partial delivery is not a plan; it is incomplete work.
2. **No capability amputation** — do not drop, weaken, or defer existing related behavior just to make the new work easier. Adjacent features, APIs, invariants, UX paths, tests, docs, and contracts that the change touches must keep working unless the user explicitly asks to remove them.
3. **No performance amputation** — do not regress latency, throughput, memory, I/O volume, or algorithmic cost class just to simplify the change. Keep existing performance characteristics of touched paths, or improve them when the goal requires it. A plan that trades known hot-path cost for coding convenience is invalid unless the user explicitly accepts that tradeoff.
4. **No silent scope cuts** — `Scope.Out` may list only true non-goals (work outside the request, or work the user explicitly excluded). Never park required work under `Out` as a shortcut.
5. **Lean among complete options** — once the full goal and preservation constraints are fixed, choose the smallest path that still meets them: existing pattern -> stdlib/native -> installed dependency -> minimal new code.

If completeness and leanness conflict, keep completeness. Prefer a longer plan over a mutilated one. If performance preservation and coding convenience conflict, keep performance.

## Workflow

1. Identify the full goal and intended outcome from the latest user request. Expand implied requirements that are necessary for the goal to be real (call sites, contracts, migrations, tests, docs that the change invalidates).
2. Inspect the context needed for current state, constraints, touch points, and adjacent behavior that must survive the change.
3. Separate hard constraints from narrow assumptions. Name missing facts instead of inventing them.
4. After local inspection: if one or more **blocking decision forks** remain — mutually exclusive choices that change architecture, scope, sequencing, or Preserve constraints, and cannot be resolved from available context — stop and ask the user before printing the plan. Prefer a short structured question with 2–4 concrete options when the runtime supports it; otherwise ask the same choices in plain text. Recommend a default option when one is defensible. Non-blocking unknowns stay under `Assumptions`.
5. Map **must-preserve** behavior and cost: existing public APIs, user-visible paths, data integrity, tests, sibling features that share the same code path, and known performance characteristics of touched hot paths (latency, throughput, memory, I/O, complexity class).
6. Choose the leanest implementation path that still satisfies full goal delivery, capability preservation, and performance preservation.
7. Explain the approach, show a concise ASCII visual, add a one-sentence plain-language summary, then decompose into dependency-ordered steps using the outcome-first step format below.
8. Run a completeness self-check before printing: every requested outcome is in steps/checklist; no required work is hidden in `Out`; must-preserve items are explicit.
9. End with the exact confirmation line unless the latest request already selects `revise`, `run`, `run-verify`, or asks for no confirmation. `ask` answers questions only and must still end with the confirmation line.

## Output Format

```markdown
## Plan

### Goal
<One paragraph with the full goal and intended outcome. No partial framing.>

### Assumptions
- <None, or narrow assumptions used to complete the plan.>

### Scope
- In: <all work required for full goal delivery>
- Preserve: <adjacent behavior/contracts/paths that must keep working; include performance of touched hot paths when relevant>
- Out: <only true non-goals or user-excluded work>

### Dependencies / Risks
- <None, or items that affect sequencing, correctness, or preservation.>

### Checklist
- [ ] <Concrete item that must be true after implementation, including preservation checks.>

### Implementation Approach
<A concise explanation of how the implementation will achieve the full goal without cutting adjacent capabilities.>

```text
<ASCII visual: for UI/layout/CLI screens or other user-visible surfaces, a simple preview of the surface; otherwise flow, layers, or touch points.>
```

In one sentence: <State the core solution in short, plain language.>

### Implementation Steps
1. <Action describing the concrete outcome in plain language>
   - location: <modify `inspected/path` (`symbol` or area), or create `proposed/path` under an inspected directory>
   - today: <current behavior>
   - change: <what this step does>
   - verify: <check>

Confirm: proceed? (revise / ask / run / run-verify)
```

## Output Rules

- Match the user's language for all user-facing plan output.
- Use the section order shown above.
- Under `Implementation Approach`, include a short ASCII visual (fenced `text` block). If the change is a UI, layout, CLI screen, or other user-visible surface, make that block a simple preview of the surface; otherwise show flow, layers, or touch points.
- Use `None` when a section has no content.
- Start each implementation step with an action verb describing its concrete outcome in plain language; put paths and symbols in the `location` sub-line, not the title.
- Every step must include `location`, followed by three separate sub-lines: `today`, `change`, `verify`. For existing files, name a concrete inspected path and symbol/area when known. For new files, label the path as proposed and ground its placement in an inspected directory. Put unresolved locations under `Assumptions` or `Dependencies / Risks`; do not present them as inspected facts.
- Do not pack today/change/verify onto one line.
- Every step must map to real work under `Scope.In`; do not restate Scope or the ASCII visual as steps.
- Keep `Dependencies / Risks` to items that change sequencing, correctness, data safety, security, preservation (capability or performance), or verification.
- Make `Checklist` concrete enough to verify full goal delivery, must-preserve behavior, and must-preserve performance.
- Include preservation checks in `Checklist` whenever the change touches shared paths, public APIs, data, multi-caller code, or hot paths.
- When a hot path is touched, checklist must include at least one concrete performance check (complexity class, benchmark, profiling note, or measured budget) — not a vague "should stay fast".
- Omit discussion history, rejected alternatives, product roadmaps, and speculative future work that is not required by the goal.
- Do not write code, edit files, or run implementation commands while producing the initial plan.
- End with `Confirm: proceed? (revise / ask / run / run-verify)` unless the latest request selected `revise`, `run`, `run-verify`, or asked for no confirmation. After `ask`, always reprint the confirmation line.

## CHECKPOINT

STOP before implementation after printing the plan. Continue only when the latest request contains:

- `revise`: incorporate changes and reprint the complete plan.
- `ask`: answer the user's question(s) about the latest plan or related local context; do not implement, edit files, or run implementation commands. End with the confirmation line.
- `run`: implement the latest complete plan.
- `run-verify`: implement, then verify with an independent subagent.
- No-confirmation wording: omit the confirmation line; implement only if the request also authorizes implementation.

## Ask Option

1. Treat `ask` as Q&A only. Do not enter `run` or `run-verify`.
2. Answer from the latest complete plan and available local context. Inspect code/files when needed to answer accurately.
3. Keep the answer scoped to the question; do not rewrite the whole plan unless the user also says `revise`.
4. If the answer reveals the plan should change, say so briefly and suggest `revise`; do not silently rewrite and proceed.
5. Always end with `Confirm: proceed? (revise / ask / run / run-verify)`.

## Run Option

1. Implement the latest complete plan directly when it fits one agent thread.
2. For large plans, split work into independent subagent tasks by file, subsystem, or checklist slice. Each slice still inherits the full plan's Preserve constraints, including performance.
3. Give each implementation subagent its scope, relevant steps, checklist items, and must-preserve constraints (capability + performance).
4. Keep the main agent responsible for integration, conflicts, preservation, and final checklist coverage.
5. Report what changed, which checklist items passed, and confirm no required capability or performance characteristic was dropped.

## Run-Verify Option

1. Complete the run option first.
2. Copy the plan's `Checklist` verbatim into the verification subagent prompt, including Preserve items.
3. Ask the subagent to inspect the real diff and relevant files against that `Checklist`.
4. Report pass/fail with checklist evidence.
5. If verification fails, fix only failed checklist items, launch a fresh independent verification subagent with the same `Checklist`, and repeat until the subagent reports no issues or a real blocker prevents completion.
6. If no verifier can run, report verification unavailable and do not claim checklist pass.

## Failure Handling

| Trigger | Action |
|---|---|
| No latest complete plan exists for `ask`, `run`, or `run-verify` | Print a plan first and stop at the checkpoint. |
| `ask` is selected | Answer only; do not implement; end with the confirmation line. |
| Required context is missing | List the missing fact under `Assumptions` or `Dependencies / Risks`; do not fabricate files, APIs, or commands. |
| Blocking decision fork remains after local inspection | Ask the user (structured options if available, else plain text); do not assume a branch and print a plan on the wrong path. |
| Requested goal is large | Split into ordered phases that still add up to full delivery; do not ship a permanently reduced goal. |
| A step lacks a verification target | Rewrite that step before final output. |
| Plan would remove or weaken adjacent capability to simplify work | Reject that plan; rewrite so the capability is preserved or explicitly approved for removal by the user. |
| Plan would regress performance of a touched path to simplify work | Reject that plan; rewrite to preserve cost class / budget, or get explicit user approval for the tradeoff. |
| Verification fails | Fix only failed checklist items, then rerun independent verification until the subagent reports no issues or a real blocker prevents completion. |

## Anti-Patterns

Do not:

- Amputate adjacent features, APIs, tests, docs, or user paths just to make the plan shorter.
- Regress latency, throughput, memory, I/O, or algorithmic cost class of a touched path just to make the change easier.
- Move required work into `Scope.Out` or "later" without user approval.
- Deliver a stub, partial path, or single-caller fix when the goal needs the whole surface.
- Turn the plan into a design essay or product roadmap.
- Ask broad clarification questions before inspecting available local context.
- Ask decision-fork questions for facts discoverable in local context, or for non-blocking preferences that do not change the plan.
- Bind the decision-fork step to one specific questioning tool; keep it runtime-agnostic.
- Add speculative abstractions, new dependencies, or future-proofing not required by the goal.
- Treat assumptions as facts.
- Claim verification passed without a real check or verifier result.
- Continue implementing after the plan unless the latest request authorizes it.
- Treat `ask` as authorization to implement, edit files, or skip the confirmation line.

## Boundary

Planning is complete when both conditions hold:

1. The user can identify the final outcome, main changes, execution order, and material risks from the plan, and can point to a specific step to correct the AI's intended work.
2. A capable agent can start work from the steps and checklist without rereading the conversation or deciding the core approach again, deliver the full requested outcome, and leave must-preserve behavior and performance intact.
