---
name: simple-plan
description: "Plan implementation before coding, with verifiable outcomes and preserved behavior and performance. Use when the user requests a plan or plan-before-coding, or selects the planning controls revise, ask, run, or run-verify, even if the plan is missing. Requests to edit or review this skill are not planning invocations."
---

# Simple plan

Produce a complete implementation plan that the user can correct and an agent can execute without deciding the core approach again. Choose the smallest implementation that delivers the full requested outcome.

## Select the mode

Interpret the latest request by intent, not by finding keywords in quoted text, code, or filenames. Control words apply to the active plan, not to unrelated requests. Editing this skill follows the user's editing request, not the planning checkpoint below.

| Request | Action | Where to stop |
|---|---|---|
| New plan | Inspect context and produce a complete plan. | At the checkpoint. |
| `revise` | Incorporate the requested changes and reprint the complete plan. | At the checkpoint, unless execution is also explicitly authorized. |
| `ask` | Answer the question using the active plan and relevant local evidence. If the answer changes the approach, identify the affected step without silently revising it. | After the answer and confirmation line. No implementation. |
| `run` | Execute the latest complete plan using the execution rules below. | After reporting checklist results or a blocker. |
| `run-verify` | Execute the latest complete plan, then obtain independent verification. | After reporting verified results or a blocker. |
| No-confirmation wording | Omit the confirmation line. This alone does not authorize execution. | After the plan unless implementation is also explicitly authorized. |

If `run` or `run-verify` has no complete plan to execute, produce one and stop at the checkpoint. If the goal is also missing, ask for it. For `ask` without a plan, answer a self-contained question from available evidence; ask for the missing plan only when the question depends on it.

For combined requests, honor explicit sequencing such as "revise, then run" or "answer, then implement." If it is unclear whether the user wants execution, ask one focused question before writing files. Authorization from an earlier turn does not override a newer plan-only or Q&A request.

## Build the plan

Planning permits read-only inspection. Do not edit files, install dependencies, or run commands that implement the change while preparing the plan.

1. **Establish the outcome.** Extract every requested result, exclusions, and hard constraints. Include necessary integration work such as affected callers, contracts, data changes, tests, and invalidated docs. Add only work required to deliver the goal, not speculative improvements.
2. **Inspect the affected paths.** Read the relevant code, configuration, tests, and directory structure. Identify current behavior, shared callers, and known hot-path costs. Use existing context when sufficient; investigate facts available locally before asking the user.
3. **Resolve blocking decisions.** If mutually exclusive choices change architecture, scope, execution order, or preservation requirements and evidence cannot resolve them, ask before printing a plan. Use 2-4 concrete options, with a recommendation when justified. Use structured questions when supported, plain text otherwise. Put non-blocking unknowns in the relevant step's `note`. Missing evidence that prevents choosing an executable approach is a blocker, not a note.
4. **Choose and sequence the implementation.** Prefer existing project patterns, then standard-library or native APIs, installed dependencies, and minimal new code. Order steps by actual dependencies. Large goals may use phases, but every phase needed for delivery belongs in the plan.
5. **Check coverage.** Map each requested outcome and preservation requirement to an implementation step and a verifiable checklist item. Each step must name its location, current behavior, intended change, and verification target. Print the plan only when no required outcome or blocking decision is left unresolved.

## Preservation requirements

Preserve related behavior unless the user explicitly approves changing it. Cover public APIs, user-visible paths, data integrity, shared callers, sibling features, tests, and documentation contracts affected by the change. Do not remove tests or weaken assertions to conceal regressions. User-requested removals are part of the goal, not preservation failures.

Preserve known latency, throughput, memory use, I/O volume, and algorithmic complexity on touched paths. A simpler implementation does not justify a known regression. If a tradeoff is necessary, obtain explicit approval before treating it as accepted.

For a touched hot path, include a concrete performance check: a complexity comparison, benchmark, profile, or measured budget relevant to the change. If no baseline exists, plan to establish one before modifying that path. Do not invent measurements or promise measured equivalence from code inspection alone.

## Plan format

Match the user's language in prose. Keep the section order and step fields below; use the literal confirmation line defined under Checkpoint. Keep the plan as short as the complete goal allows. Do not add separate assumptions, scope, or risks sections; attach material constraints to the affected steps.

````markdown
## Plan

### Goal
<Full requested outcome and intended observable result.>

### Checklist
- [ ] <Verifiable outcome or preservation requirement; identify the step that covers it.>

### Implementation Approach
<How the implementation delivers the goal while preserving affected behavior and cost.>

```text
<Concise ASCII visual: for UI/layout/CLI screens, preview the changed surface.
Otherwise show the relevant flow, layers, or touch points.>
```

In one sentence: <Core solution in plain language.>

### Implementation Steps
1. <Action verb and concrete outcome, without paths in the title>
   - location: <Inspected file and symbol/area, or proposed new path under an inspected directory>
   - today: <Current behavior supported by inspection>
   - change: <Specific implementation work>
   - verify: <Check and observable pass condition>
   - note: <Only when needed: assumption, unresolved non-blocking fact, risk, or sequencing constraint>
````

Use separate `location`, `today`, `change`, and `verify` lines in that order. Omit `note` when unnecessary. Mark proposed paths as proposed; if an exact location is unresolved, name the inspected parent area and use `note` to specify how it will be located. Never present a guessed file, API, or command as an inspected fact. Partial evidence establishes only what it shows: seeing one export or test does not prove that others are absent. Verify absence before claiming it, or state the narrower known fact.

Use commands discovered in the project when known. Otherwise describe the required check and how its command will be identified. Include success criteria, not just "run tests." Keep checklist items unchecked until execution supplies evidence. Omit discussion history, rejected alternatives, roadmaps, and unrelated future work.

## Checkpoint

After an initial or revised plan, STOP before implementation unless the latest request explicitly authorizes it and a complete plan is available.

End plan-only and Q&A responses with exactly this line, except when the user requests no confirmation:

`Confirm: proceed? (revise / ask / run / run-verify)`

## Execute the plan

1. Recheck relevant files against the plan before editing. Work with existing user changes. If new evidence invalidates the approach or requires a material scope or preservation tradeoff, report it and resolve the decision before proceeding. Local implementation details that do not change the agreed outcome can be resolved during execution.
2. Implement the dependency-ordered steps. Use one agent for tightly coupled work. Delegate only independent work with clear file or subsystem ownership; provide each agent its steps, checklist items, and behavior and performance requirements. The main agent owns integration and full checklist coverage.
3. Run the planned checks for `run` as well as `run-verify`. Record each checklist item as passed, failed, or unverified, with command results or file evidence appropriate to the claim. A failing check is a failure; unavailable tools or environments leave the item unverified. Fix failures within the agreed scope. Report blockers explicitly rather than reducing the goal or claiming success.
4. For `run`, report the implemented outcome and checklist results. For `run-verify`, continue below before reporting completion. Distinguish implementation completion from verified behavior and measured performance.

## Independent verification

1. Give a read-only verification subagent the complete plan, its Checklist verbatim, the actual changed-file scope, and executed check results. Ask it to inspect the real diff and relevant callers and tests, run feasible checks, and report evidence per item plus regressions introduced by the changes. If no verifier can run, report independent verification unavailable; do not substitute self-review and call it independent.
2. Assess findings against the files and observed behavior. Fix confirmed failures and introduced regressions, including ones omitted from the original checklist. If a missing requirement is found, update the plan and checklist explicitly; obtain approval for material scope changes. A disputed finding needs counterevidence, not dismissal.
3. After fixes, run the relevant checks and request a fresh independent verification against the full current checklist, identifying any checklist changes. Repeat while confirmed failures remain and can be addressed. If progress requires unavailable evidence, tools, access, or a user decision, report that blocker and leave the affected items unverified or failed.
4. Report each checklist item's status with evidence. A verifier's "no issues" does not turn unrun checks into passes. Completion requires all required items to pass; otherwise state what remains incomplete.
