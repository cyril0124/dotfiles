---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Use the `question` tool to ask questions. If multiple questions have no dependency on each other, batch them into a single `questions` array. When providing options, mark the recommended one with "(Recommended)" so the user has a clear reference.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Closing phase

When all branches are resolved and no further questions remain, produce a final summary in this format:

```markdown
## Design Summary

### Decisions Made
- <Decision>: <chosen answer> — <one-line rationale>

### Scope
- <What this plan covers>
- <What is explicitly out of scope>

### Suggested Skills
- <skill-name> — <one-line reason it helps>

Confirm: proceed with implementation? (yes / yes-verify / no / revise / save / show / to-add)
```

Rules for `### Suggested Skills`:
- Always include the section. If no skill is a good fit, write a single bullet: `- None`.
- Only recommend skills that are loadable in the current session's `<available_skills>` list. Do not recommend skills the user has not installed.
- Keep each bullet to one line: skill name plus a brief reason it applies to this plan.

Do not implement until user says "yes" or "yes-verify".

### Yes-verify option

On **yes-verify**, do same as **yes**, then launch independent subagent to verify before completion report.

Subagent verify rules:
- Use general-purpose subagent unless specific verify/review subagent clearly fits.
- Subagent verify implementation against final `Design Summary`: decisions, scope, acceptance checklist, validation plan.
- Subagent inspect real diff + relevant files, not implementer summary only.
- Implementer wait for subagent result, then report pass/fail.
- If fail: summarize findings, fix, re-run independent subagent verification.
- Repeat fix-and-verify loop until subagent passes, or real blocker prevents completion.
- Implementer cannot accept own work without passing independent subagent result.

### To-ADD option

On **to-add**, write the grill outcome as an Architecture Design Document (ADD), using an arc42-inspired structure by default:

1. Detect whether an ADD for the current topic/system already exists before creating a new file.
   - First inspect likely locations in the current repo: `docs/architecture/`, `docs/design/`, `architecture/`, `design/`, `docs/`, `doc/`.
   - Look for filenames/titles such as `architecture-design.md`, `software-architecture.md`, `architecture.md`, `design.md`, `add.md`, or topic-specific architecture/design documents.
   - Use filename/title/topic matching against the plan topic, system name, feature name, and major components.
   - If a likely existing document is found, read it and enrich it instead of creating a duplicate.
2. If an existing ADD is found, preserve its accepted facts and local structure while adding missing detail from the grill result:
   - overview / concise purpose and scope
   - constraints
   - system scope/context
   - solution strategy
   - technology stack
   - building-block/component view
   - runtime flows
   - deployment view
   - cross-cutting concepts
   - key design decisions
   - quality requirements
   - risks/technical debt
   - validation plan
   - acceptance checklist
   - glossary/links when useful
3. If no existing ADD is found, create a new Markdown ADD.
   - Prefer an existing architecture/design docs directory if present.
   - Otherwise create `docs/architecture/`.
   - Filename: `architecture-design-<topic-slug>.md` for topic-specific designs, or `architecture-design.md` for repo/system-level designs.
4. Use this structure unless the existing file has a clear local convention. Treat it as a section menu, not a mandatory checklist: include only sections that help explain the design, and omit empty or irrelevant sections.

```markdown
# Architecture Design Document: <System / Feature Name>

## Overview

Summarize purpose, scope, core design, key decisions, and how to read this document. Concise only; no acceptance details.

## Related Documents

- <URL or relative path from this ADD file to the related document>

## 1. Architecture Constraints

## 2. System Scope and Context

## 3. Solution Strategy

## 4. Technology Stack

Summarize the concrete technologies, frameworks, infrastructure, data stores, protocols, and tools chosen for this design, plus the reason each major choice matters.

## 5. Building Block View

## 6. Runtime View

## 7. Deployment View

## 8. Cross-cutting Concepts

## 9. Key Design Decisions

## 10. Quality Requirements

## 11. Risks and Technical Debt

## 12. Validation Plan

## 13. Acceptance Checklist

Use checkboxes for end-to-end acceptance criteria. Each checkbox validates full user/system flow: trigger/input → processing → observable outcome. Independent subagent must verify acceptance; implementing agent cannot accept own work. When every checkbox has evidence, ADD is implemented + accepted. Evidence: review, tests, metrics, demos, rollout checks, or production proof.

## 14. Glossary
```

   Section selection rules:
   - Always include `Overview` and `Acceptance Checklist`.
   - Usually include `System Scope and Context`, `Solution Strategy`, `Technology Stack`, and `Key Design Decisions` for a meaningful ADD.
   - Do not include `Introduction and Goals`; put high-level purpose + scope in `Overview`.
   - Include `Related Documents` only when useful links or paths exist; file paths must be relative to the ADD file that contains the link.
   - Include `Architecture Constraints` only when constraints materially shape the design.
   - Include `Technology Stack` when concrete technology choices affect implementation, operations, compatibility, or acceptance; keep it as a concise stack/rationale summary and avoid duplicating detailed component, runtime, or deployment views.
   - Include `Building Block View`, `Runtime View`, and `Deployment View` only when those views clarify the design.
   - Include `Cross-cutting Concepts`, `Quality Requirements`, `Risks and Technical Debt`, `Validation Plan`, and `Glossary` only when they add non-obvious information.
   - Write `Acceptance Checklist` as end-to-end implementation acceptance checkboxes, not vague goals, documentation tasks, or component-local TODOs.
   - Keep acceptance criteria out of `Overview`; `Acceptance Checklist` is only verifiable acceptance source.
   - Independent subagent verifies checklist; implementing agent cannot accept own work.
   - The checklist must be complete enough that checking every item means the ADD has been fully implemented and accepted.
   - Never emit placeholder sections with no useful content.

5. If the ADD would become too long to stay readable or safe to edit, split it into an index document plus detail pages instead of writing one giant file.
   - Keep the main ADD as the entry point with goals, scope, solution strategy, key decisions, and links to details.
   - Put large sections into sibling files, for example:
     - `context.md`
     - `technology-stack.md`
     - `building-block-view.md`
     - `runtime-view.md`
     - `deployment-view.md`
     - `cross-cutting-concepts.md`
     - `quality-requirements.md`
     - `risks-and-validation.md`
   - For new split topic-specific designs, use a topic folder to avoid name collisions:

```text
docs/architecture/<topic-slug>/
├── README.md
├── context.md
├── technology-stack.md
├── building-block-view.md
├── runtime-view.md
├── deployment-view.md
├── cross-cutting-concepts.md
├── quality-requirements.md
└── risks-and-validation.md
```

   - If a topic folder cannot be used, prefix companion pages with the topic slug, for example `<topic-slug>-runtime-view.md`.
   - If enriching an existing large ADD, avoid rewriting the whole document. Patch only the relevant section, or create a focused companion page and link it from the main ADD.
   - Do not duplicate the same content in both the index and detail pages; the index summarizes, detail pages explain.
6. After writing, tell the user whether the ADD was created, enriched, or split, and show the file path(s).
7. Implementation is **not** started — "yes" to proceed, "revise" to revisit.
8. Re-prompt: `Confirm: proceed with implementation? (yes / yes-verify / no / revise / save / show / to-add)`

### Save option

On **save**, write summary to file:

1. Filename: `plan-<topic-slug>.md` (topic lowercased, spaces→`-`, strip non-alnum/dash).
2. If exists, try `plan-<topic-slug>-1.md`, then `-2.md`, etc.
3. Write full Design Summary (Decisions Made + Scope + Suggested Skills). Do not include the "Confirm" prompt line in the file.
4. Tell user filename; implementation **not** started — "yes" or "yes-verify" to proceed, "revise" to revisit.
5. Re-prompt: `Confirm: proceed with implementation? (yes / yes-verify / no / revise / save / show / to-add)`

### Show option

On **show**, render design as ASCII architecture diagram:

1. Use box-drawing chars (`─`, `│`, `┌`, `┐`, `└`, `┘`, `├`, `┤`, `┬`, `┴`, `┼`) for components, data flow, relationships, layers.
2. Bird's-eye view of final design, not discussion process.
3. Re-prompt: `Confirm: proceed with implementation? (yes / yes-verify / no / revise / save / show / to-add)`
