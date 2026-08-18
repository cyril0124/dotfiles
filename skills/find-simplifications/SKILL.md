---
name: find-simplifications
description: 'Identify evidence-backed simplification candidates across a codebase: dead code, speculative abstractions, duplicated state, defensive bloat, over-engineering, or hand-rolled logic where standard libraries/dependencies exist. Produces structured, verified de-bloating proposals grouped into Tier A/B/C with call-site proof and risk analysis.'
---

# Finding Codebase Simplifications

This skill guides you in auditing a codebase to find non-obvious simplification candidates, eliminate over-engineering, and produce **evidence-backed** proposals to remove or collapse unnecessary surface area.

## Core Philosophy

- **Subtraction over addition**: The best code is the code never written.
- **Evidence-first**: Never claim code is unused or over-engineered based on inspection or intuition alone. Prove it with strict call-site analysis across the codebase.
- **Root-cause consolidation**: Replace fragmented defensive checks or multiple lifecycle controllers with a single authoritative boundary or owner.
- **Propose only**: Report candidates. Do not apply deletions or rewrites unless the user explicitly asks.

---

## 1. What Counts as a Strong Simplification Candidate

Look for patterns where complexity costs more than the value it delivers:

1. **Dead or Orphan Surface Area**:
   - A public method, class, exported helper, config knob, CLI flag, or event that has **zero callers in production code** (only tests, old docs, or nothing calls it).
2. **Duplicated / Mirrored State**:
   - The same domain fact is stored or tracked in two places (e.g., in an in-memory map AND a persistent event log, or synchronized across multiple mutable state objects).
3. **Speculative Abstractions (YAGNI Violations)**:
   - Interfaces with exactly one implementation.
   - Factories producing a single variant.
   - Extension points, plugin slots, or hook registries with no real consumers.
   - Unrequested generic parameterization and configurable toggles for constants that never change.
4. **Reinventing the Platform / Stdlib**:
   - Hand-rolled diffing, string hashing, event emitters, stream readers, glob matchers, or retry loops where runtime built-ins (Node/Bun/browser) or established project dependencies already provide robust implementations.
5. **Defensive Machinery Bloat**:
   - Excessive defensive copies (`structuredClone`, deep freezes), defensive null-checks, or runtime type assertions across safe, internal, statically-typed same-process boundaries.
6. **Fragmented Lifecycle Controllers**:
   - Multiple boolean flags (`isDisposed`, `isCancelled`, `isClosed`, `isRunning`), timeout handles, and sentinel promises trying to coordinate the same asynchronous operation. Propose a single lifecycle controller or `AbortController`/disposer instead.

---

## 2. Classification & Call-Site Proof (The Evidence Bar)

Before proposing any deletion or simplification, classify the codebase into three corpora:

- **Production Corpus**: Core source files (`src/`, `lib/`, runtime scripts).
- **Non-Production Corpus**: Unit/E2E tests (`test/`, `*.test.ts`), documentation (`docs/`, `README.md`), test fixtures, benchmarks.
- **Configuration & External Bindings**: Entrypoints, package manifests (`package.json`), CLI bindings, public exports.

### Verification Steps

1. **Search with `rg`**:
   - Search exact symbol names, property accesses (`.foo(`, `.foo`), string literals, event keys, and CLI flags across the production corpus.
2. **Rule Out Dynamic & Indirect Usage**:
   - Check reflection, dynamic property access, dependency injection, and framework conventions before declaring code dead.
3. **Check Test Purpose**:
   - If tests are the **only** callers of a function or class, determine if the test is validating a required contract or merely asserting on an obsolete internal helper.

If the searches show the surface is actually used, or you cannot form a concrete candidate, do not report it. A concrete candidate with leftover dynamic-usage, DI, or ownership doubt is Tier C, not a drop.

---

## 3. Tier Assignment

Every candidate that passes the evidence bar gets exactly one tier. Walk the checks in order and stop at the first match.

1. **Drop (do not report)** if it hits a hard exclusion in section 5.
2. **Tier C — Needs your decision, do not edit** if a human must choose before any edit:
   - Documented public contract or extension point for external users.
   - Change that contradicts or reinterprets an ADR.
   - Product or design tradeoff (keep the flexibility vs. delete it).
   - Residual search ambiguity that `rg` and the dynamic-usage check cannot close.
   - Blast radius that is not local and has no agreed owner.
   Do not implement Tier C in the same pass.
3. **Tier B — High value, needs regression** if evidence is closed enough for a concrete edit, but the change is not locally revertible:
   - Shared path, multiple production callers, or a behavior-preserving rewrite.
   - Duplicated state, lifecycle consolidation, or stdlib swap that needs a regression check to prove equivalence.
   Implement only after the named verification runs.
4. **Tier A — Evidence closed, risk near** if all of these hold:
   - Call-site proof is closed: no leftover dynamic, reflection, DI, or framework-convention doubt.
   - Change is local (one module or a dead surface).
   - No public or exported contract.
   - Effect is deletion of unused surface, or a mechanical swap for an equivalent stdlib/native API.
   - Revert is mechanical.
   Safe to act on directly.

Every candidate needs one line stating why it landed in that tier.

Follow the user's language for explanations. Keep the three English tier headings exactly as written above. Keep paths and symbols as they appear in the code.

---

## 4. Proposal Format

Number candidates sequentially (`1`, `2`, `3`, …) in report order: all A, then all B, then all C. Omit any tier that has no candidates.

If nothing passes the evidence bar:

```markdown
No simplification candidates found.
```

Otherwise start with the summary table, then the tier sections.

```markdown
## Simplification Candidates

| ID | Tier | Title | Net Delta |
|----|------|-------|-----------|
| 1 | A | Remove unused session summary cache | -80 / +0 |
| 2 | B | Collapse duplicated request lifecycle flags | -200 / +20 |
| 3 | C | Drop documented plugin slot with no in-repo consumer | -40 / +0 |

## Tier A — Evidence closed, risk near

### [Candidate 1]: Remove Unused Session Summary Cache

- **Target / Location**: `path/to/file.ts:line` (or affected modules)
- **Problem & Evidence**:
  - What complexity exists today?
  - Production call-site proof (e.g., `rg` confirms 0 callers in `src/`).
- **Proposal**:
  - What exact functions, types, fields, or files to delete/merge.
  - What native API, existing utility, or single owner replaces it.
- **Why was it added / Counter-argument**:
  - Why was this written in the first place? (e.g., speculative caching, premature abstraction).
- **Risks & Tradeoffs**:
  - Any subtle edge cases, public API changes, or downstream impacts.
- **Net Delta**: Estimated lines deleted vs. added (e.g., `-120 lines, +5 lines`).
- **Tier reason**: Evidence closed and the change is local / mechanically revertible.

## Tier B — High value, needs regression

### [Candidate 2]: Collapse Duplicated Request Lifecycle Flags

- **Target / Location**: `path/to/file.ts:line`
- **Problem & Evidence**:
  - ...
- **Proposal**:
  - ...
- **Why was it added / Counter-argument**:
  - ...
- **Risks & Tradeoffs**:
  - ...
- **Net Delta**: `-200 lines, +20 lines`
- **Verify with**: The concrete test, command, or check that must pass before editing.
- **Tier reason**: Evidence closed, but shared callers need a regression check.

## Tier C — Needs your decision, do not edit

### [Candidate 3]: Drop Documented Plugin Slot With No In-Repo Consumer

- **Target / Location**: `path/to/file.ts:line`
- **Problem & Evidence**:
  - ...
- **Proposal**:
  - ...
- **Why was it added / Counter-argument**:
  - ...
- **Risks & Tradeoffs**:
  - ...
- **Net Delta**: `-40 lines, +0 lines`
- **Decision needed**: The question the user must answer before any edit. Do not change this in the current pass.
- **Tier reason**: Public contract / ADR / residual ambiguity / needs an owner.
```

Field rules:

- Every candidate keeps **Target / Location**, **Problem & Evidence**, **Proposal**, **Why was it added / Counter-argument**, **Risks & Tradeoffs**, **Net Delta**, and **Tier reason**.
- Tier B also requires **Verify with**.
- Tier C also requires **Decision needed**, and must say not to edit it in this pass.
- Do not invent candidates to fill a tier. Omit empty tier headings and omit the summary table when there are no candidates.

---

## 5. When NOT to Report

Do **not** put these in any tier:

- Defensive boundaries at true trust boundaries (untrusted user input, JSON deserialization, IPC, network, file I/O).
- Code required by a known platform quirk to stay correct.
- Mechanical micro-optimizations that create high churn without reducing cognitive load or maintenance cost.

Report these as **Tier C**, do not drop them, and do not edit them in the same pass:

- Core public contracts and extension points that are intentionally documented for external users.
- Changes that contradict or reinterpret an ADR.
- Residual call-site ambiguity that section 2 cannot close.
- Product or design tradeoffs where keeping the extra surface is a legitimate choice.
