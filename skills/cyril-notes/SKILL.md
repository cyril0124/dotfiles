---
name: cyril-notes
description: "Read and answer questions from personal notes. Use when the user asks about their notes, wants to search or recall something from notes, or references knowledge they previously wrote down. Trigger on: 'my notes', 'check my notes', 'notes say', 'in my notes', 'look up notes', or any question that implies consulting a personal knowledge base. Do not use for general knowledge questions unrelated to the user's own notes."
---

# Cyril Notes

Answer questions from user's personal notes.

## When to use

- User implies answer lives in notes.
- User says "check my notes", "what do my notes say", "look up X in my notes".
- User references a topic they wrote notes on.

## When not to use

- General knowledge questions with no note-related intent.
- Tasks not involving reading/searching notes.

## Workflow

1. Resolve notes dir from `NOTES_DIR` env var.
   - If `NOTES_DIR` unset/empty, **refuse execution**. Report error and stop. Do not guess or fall back to default path.
2. Read `$NOTES_DIR/AGENTS.md` if it exists. All answers and behavior must follow the rules and conventions defined there.
3. List `$NOTES_DIR` contents to understand structure.
4. Search relevant files based on question:
   - Glob by name pattern.
   - Grep content for keywords.
   - Start narrow, widen if needed.
5. Read most relevant files. Read enough context — don't stop after single match if topic spans files.
6. Synthesize answer from notes, following AGENTS.md rules. Cite source file(s).

## Common pitfalls

- **NOTES_DIR not set**: Fail fast with clear message. Never silently fall back to guessed path.
- **Skipping AGENTS.md**: Always read `$NOTES_DIR/AGENTS.md` first. It overrides defaults and defines project-specific rules.
- **Reading too little**: Topic may span files. Search broadly before concluding "not found".
- **Hallucinating beyond notes**: State only what notes say. If not covered, say so explicitly.
- **Skipping AGENTS.md**: Always read `$NOTES_DIR/AGENTS.md` first. It overrides defaults and defines project-specific rules.

## Output requirements

- Answer grounded in actual notes content.
- If found, cite relative file path under `NOTES_DIR`.
- If not found, state clearly that notes don't contain the info.
