---
name: cyril-notes
description: "Read and answer questions from the user's personal notes. Trigger on: 'my notes', 'check my notes', 'notes say', 'in my notes', 'look up notes', '笔记里', '我的笔记', '查笔记'. Do not use for general knowledge without note-related intent."
---

# Cyril Notes

Answer questions from the user's personal notes directory (`$NOTES_DIR`).

## TL;DR

```
Check $NOTES_DIR → Read $NOTES_DIR/AGENTS.md → Search (glob + grep) → Read → Synthesize with citations
```

## When to use

- User implies answer lives in notes.
- User says "check my notes", "what do my notes say", "look up X in my notes", "笔记里有没有".
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
- If the user's question is too broad (e.g., "笔记里写了什么？", "what's in my notes?"): list the top-level structure and prompt the user to narrow down the topic before searching.

### Step 4 — Search relevant files

Use both strategies, starting narrow and widening if needed:

| Strategy | Command pattern | When to use |
|----------|-----------------|-------------|
| Name match | `glob "$NOTES_DIR/**/*{keyword}*"` | User mentions a specific topic/concept |
| Content match | `grep -r "keyword" "$NOTES_DIR"` | Name match yields nothing or too little |

- If initial keywords yield no results, try synonyms or broader terms.
- If still no results after 2-3 search rounds, proceed to Step 6 and report "not found".

### Step 5 — Read and verify

- Read the most relevant files entirely (not just matching lines).
- If topic spans multiple files, read all of them.
- **Verify semantic relevance**: ensure the matched content actually answers the user's question, not just contains the keyword. If a match is a false positive (e.g., "部署" in hardware context vs. project deployment), discard it and continue searching.

### Step 6 — Synthesize answer

- Base answer strictly on notes content.
- Cite source files using relative paths under `$NOTES_DIR`.
- If information is not found after broad search, state clearly: `"Your notes do not contain information about X."`

## Decision checkpoints

The agent must pause for user confirmation before proceeding if:

- The user's question is too broad (e.g., "what's in my notes?", "笔记里有什么？") — show directory structure and ask them to narrow the scope.
- The search requires reading >10 files (risk of information overload / privacy exposure).
- The user question could expose sensitive personal information and the agent is unsure whether to include it.
- The matched content seems ambiguous or contradictory — confirm with the user before synthesizing.

## Common pitfalls

- **NOTES_DIR not set**: Fail fast with clear message. Never silently fall back to guessed path.
- **NOTES_DIR invalid**: Path does not exist or is not readable — report and stop, never attempt to create or fix it.
- **Skipping AGENTS.md**: Always read `$NOTES_DIR/AGENTS.md` first if it exists. It overrides defaults.
- **Reading too little**: Topic may span files. Search broadly before concluding "not found".
- **Hallucinating beyond notes**: State only what notes say. If not covered, say so explicitly.
- **Keyword false positives**: A file containing the keyword does not mean it answers the question. Always verify context.
- **Overly broad queries**: When user asks "what's in my notes", do not read all files — show structure and ask user to narrow down.

## Output requirements

- Answer grounded in actual notes content.
- Cite relative file path under `$NOTES_DIR` for every claim.
- If not found, state clearly that notes don't contain the info.
