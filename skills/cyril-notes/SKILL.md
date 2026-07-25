---
name: cyril-notes
description: "Read and answer questions from the user's personal notes. Trigger on: 'my notes', 'check my notes', 'notes say', 'in my notes', 'look up notes', or equivalent note-lookup intent in any language. Do not use for general knowledge without note-related intent."
---

# Cyril Notes

Answer questions from the user's personal notes directory (`$NOTES_DIR`).

## TL;DR

```
Check $NOTES_DIR → Read $NOTES_DIR/AGENTS.md → Structure → Progressive search → Link expand → Top-N read → Answer + Evidence
```

## When to use

- User implies answer lives in notes.
- User says "check my notes", "what do my notes say", "look up X in my notes", or equivalent.
- User references a topic they wrote notes on.

## When not to use

- General knowledge questions with no note-related intent.
- Tasks not involving reading/searching notes.

## Workflow

### Step 1 — Resolve notes directory

- Read `NOTES_DIR` env var.
- If unset or empty: **stop immediately**. Report: `"Error: NOTES_DIR is not set. Cannot access notes."`
- If set but path does not exist: **stop immediately**. Report: `"Error: NOTES_DIR path does not exist: $NOTES_DIR"`
- If set but path not readable (permission denied): **stop immediately**. Report: `"Error: NOTES_DIR path is not readable: $NOTES_DIR"`
- Do not guess, do not fallback to any default path.

### Step 2 — Read AGENTS.md

- If `$NOTES_DIR/AGENTS.md` exists: read it first. All subsequent behavior must follow its rules.
- If it does not exist: proceed with defaults below.

### Step 3 — Discover structure

- List top-level contents of `$NOTES_DIR` to understand folder layout.
- If the directory is empty: report `"Notes directory is empty. No notes to search."` and stop.
- If the user's question is too broad (e.g. "what's in my notes?"): list the top-level structure and prompt the user to narrow down the topic before searching.

### Step 4 — Progressive search

1. **Extract terms** from the question: primary keywords + aliases/synonyms (include cross-language variants when the vault or question mixes languages).
2. **Narrow by structure** using Step 3: prefer topic folders, indexes, MOCs, and README-like files that match the terms. Limit later content search to those candidate subtrees when possible.
3. **Search inside candidates**, then widen only if needed:

| Order | Strategy | Scope |
|-------|----------|-------|
| 1 | Name match on files/folders | Candidate subtrees first, then whole `$NOTES_DIR` |
| 2 | Content match (`rg`) | Same narrowing, then whole `$NOTES_DIR` |
| 3 | Alias / broader terms | Only after 1–2 miss |

4. **Rank hits** before reading: path relevance to the topic > match density > generic/root files. Take Top-N (usually 1–5; stop and ask if >10).
5. **Link expand (one hop only)** from the current Top-N before deep reading:
   - Collect outbound `[[wikilinks]]` and in-vault markdown links from those hits (and from any matched index/MOC entries).
   - Resolve links that stay under `$NOTES_DIR`; ignore external URLs.
   - Re-rank the combined set: canonical / topic / evergreen notes > stubs, dailies, or passing mentions.
   - Keep the final candidate set within Top-N (usually ≤5). Do not crawl the whole graph.
6. If still no useful hits after narrowing → widen → alias → one-hop expand, proceed to Step 6 and report "not found".

### Step 5 — Read and verify

- Read the final Top-N only. Start with the matched section plus nearby context; read the full file only when the section is incomplete or the topic spans the note.
- **Verify semantic relevance**: the content must answer the question, not merely contain the keyword or appear only as a linked title. Discard false positives (e.g. "deploy" in hardware bring-up vs. app release) and continue with the next ranked hit.
- If notes conflict, prefer the more specific note; if dates or "updated" markers exist, prefer the newer one and mention the conflict.

### Step 6 — Synthesize answer

- Base answer strictly on notes content.
- Write the answer and `Evidence` labels in the **user's language** (match the language of the current user message). Keep file paths, code, and note quotes in their original form.
- Write the answer normally, then end with an `Evidence` section.
- Run the **Final checklist** on the drafted answer; fix any miss before sending.
- If information is not found after broad search, state clearly in the user's language that notes do not contain the info, and omit fabricated evidence.

## Final checklist

Last gate after drafting, before the user sees the answer:

- [ ] `NOTES_DIR` resolved; `AGENTS.md` read if present
- [ ] Search used structure first (folders/indexes), not full-vault dump
- [ ] Hits ranked; one-hop links expanded; only final Top-N read and verified as on-topic
- [ ] Answer claims come only from notes (or explicitly "not found")
- [ ] Answer language matches the user's language
- [ ] `Evidence` has `path:line` (or locatable quote); no invented citations
- [ ] Conflicts/staleness mentioned when multiple notes disagree

## Decision checkpoints

The agent must pause for user confirmation before proceeding if:

- The user's question is too broad (e.g. "what's in my notes?") — show directory structure and ask them to narrow the scope.
- The search requires reading >10 files (risk of information overload / privacy exposure).
- The user question could expose sensitive personal information and the agent is unsure whether to include it.
- The matched content seems ambiguous or contradictory — confirm with the user before synthesizing.

## Output requirements

- Answer grounded in actual notes content.
- Use the user's language for explanations, section labels the user will read, and "not found" messages. Keep paths, identifiers, and quoted note text unchanged.
- After the answer, always add an `Evidence` section for factual claims drawn from notes.
- If not found, state clearly that notes don't contain the info.

```markdown
**Evidence**
- `relative/path/under/NOTES_DIR.md:line` — what this note proves.
- Unverified: <claim or assumption> — not in notes / only inferred.
```

- Prefer `path:line` when line numbers are available; otherwise use a short quoted snippet that locates the claim.
- Paths are relative to `$NOTES_DIR`.
- Do not invent paths, line numbers, or quotes.
- Keep opinions separate from verified notes content.
