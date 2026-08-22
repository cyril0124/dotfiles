---
name: doc-standards
description: 'Use when writing, reorganizing, reviewing, or trimming documentation in a codebase. Enforces high-signal technical writing: eliminates doc slop/narrative leakage, establishes single source of truth (One Home Per Fact), separates tutorials from references, and keeps bilingual (EN/ZH) pairings synchronized.'
---

# Documentation Standards & Quality Workflow

This skill provides a systematic workflow for authoring, reviewing, and trimming technical documentation across Markdown files, JSDoc, and code comments.

## Core Principles

1. **Present State, Not Historical Narrative**:
   - Document how the system currently works today.
   - Do NOT write design session transcripts, dead alternatives without durable value, or chronological evolution ("previously we used X, then changed to Y"). Commit logs and PR descriptions own history; docs own the present reality.
2. **One Home Per Fact**:
   - Every architectural rule, configuration key, API contract, or concept must have exactly ONE authoritative home.
   - Link across documents (`[link](path/to/doc.md)`) rather than duplicating explanations.
3. **Contracts Over Syntax Narratives**:
   - Comments and JSDoc must state complete caller/callee contracts (inputs, side effects, throw conditions, concurrency, ownership), NOT step-by-step code walkthroughs that narrate obvious syntax.
4. **Bilingual Pairing (EN / ZH)**:
   - When a repository adopts bilingual documentation (`<name>.md` and `<name>.zh.md`), any modification to one language MUST synchronize to the other in the same change.

---

## 1. Review Structure Before Prose

Before writing or editing text, establish document classification and ownership:

### A. Document Hierarchy
- **Parent / High-Level Docs**: State the subject, outline architecture, summarize direct submodules by purpose, and link to descendants for detailed operations.
- **Child / Topic Docs**: Own full operational and API details for their specific domain.

### B. Tutorial vs. Reference Form
Never mix tutorial steps and exhaustive reference catalogs into a single unorganized section:

| Type | Purpose | Reader Flow | Content Rules |
| :--- | :--- | :--- | :--- |
| **Tutorial / Guide** | Teach a skill or achieve a specific goal | Step-by-step sequential reading | Linear progression, minimal distractions, prerequisites explicit, ends in a verifiable outcome. |
| **Reference / Spec** | Look up facts, APIs, options | Non-linear lookup / random access | Exhaustive, alphabetically or logically indexed, precise types/defaults/errors, self-contained items. |

---

## 2. The Anti-Slop Audit Checklist

When reviewing existing documentation or pull requests, hunt down the following documentation smells:

1. **Reasoning & CoT Leakage**:
   - Delete sentences narrating internal developer deliberations ("We thought about...", "In order to decide...").
2. **Obvious Restatements**:
   - Delete comments and docs that restate the code syntax (e.g., `// Sets name to string` above `setName(name: string)`).
3. **Hand-Rolled Duplicated Inventories**:
   - Replace manually typed lists of commands, flags, or test statuses with generated references or links to the authoritative source file.
4. **Vague Hand-Waving**:
   - Replace generic phrases ("handles various edge cases", "provides utilities") with exact paths, function names, types, error names, and bounded guarantees.
5. **Dangling & Broken Links**:
   - When moving or renaming docs, search for inbound links across both Markdown files and TypeScript/code comments. Moves must be atomic.

---

## 3. Review & Editing Workflow

When asked to "audit the docs", "improve documentation", or "trim doc slop":

1. **Identify Corpus & Scope**:
   - Locate targeted documents (`docs/*.md`, `README.md`, `README.zh.md`, inline JSDoc).
2. **Check Single Source of Truth**:
   - Grep distinctive keywords or concepts across the workspace to check if the same fact is explained multiple times. Condense into the canonical home and replace copies with relative Markdown links.
3. **Trim & Compress**:
   - Remove narrative filler and obsolete sections.
   - Retain all load-bearing invariants, parameters, and error modes in concise bullet points or tables.
4. **Synchronize Bilingual Counterparts**:
   - If editing `docs/topic.md`, verify and update `docs/topic.zh.md` (and vice versa) to ensure zero semantic drift.
5. **Verify Markdown Links**:
   - Check that all relative links and `#heading-anchors` in edited files point to existing files and valid section headers.
