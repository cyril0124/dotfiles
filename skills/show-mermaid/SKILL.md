---
name: show-mermaid
description: Use when asked for Mermaid diagram source, rather than rendered ASCII or images.
---

# Show Mermaid

Output Mermaid **source** in a fenced `mermaid` block. No SVG/ASCII render, no pretty-mermaid.

## Allowed types only

| Intent | Header |
|--------|--------|
| Flow / architecture / decision | `flowchart TD` or `LR` (legacy `graph` ok) |
| Lifecycle / protocol state | `stateDiagram-v2` (or `stateDiagram`) |
| Types / modules / OOP | `classDiagram` |
| Data model | `erDiagram` |
| Calls / messages over time | `sequenceDiagram` |

Other Mermaid kinds (gantt, pie, journey, gitGraph, mindmap, …) → closest allowed type, or refuse with this list.

## Rules

1. **Valid Mermaid only** — must parse; short labels; ids ASCII, CJK only in display text.
2. **Structure over decoration** — no `classDef` / theme / `%%{init}%%` unless asked.
3. **Output** — optional short captions; each diagram in its own ` ```mermaid ` block; no essay padding.
4. **Vs others** — ASCII Mermaid render → `show-mermaid-ascii`; box art → `ascii-visual`; themed SVG → `pretty-mermaid`.

## Type selection

```
time-ordered messages?  → sequenceDiagram
entity relationships?   → erDiagram
type/module structure?  → classDiagram
states + transitions?   → stateDiagram-v2
else process/arch       → flowchart TD|LR
```
