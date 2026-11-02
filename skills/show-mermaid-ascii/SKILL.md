---
name: show-mermaid-ascii
description: Use when asked to render Mermaid diagrams as terminal ASCII or Unicode.
---

# Show Mermaid ASCII

Author allowed Mermaid, render with `scripts/mermaid_ascii.py`, show the ASCII. Never invent box art by hand.

## Steps

1. **Pick type** (allowed only):

   | Intent | Header |
   |--------|--------|
   | Flow / architecture / decision | `flowchart TD` or `LR` (legacy `graph` ok) |
   | Lifecycle / protocol state | `stateDiagram-v2` (or `stateDiagram`) |
   | Types / modules / OOP | `classDiagram` |
   | Data model | `erDiagram` |
   | Calls / messages over time | `sequenceDiagram` |

   Other Mermaid kinds (gantt, pie, journey, gitGraph, mindmap, …) → closest allowed type, or refuse with this list.

2. **Write valid Mermaid** — must parse; short labels; ids ASCII, CJK only in display text; no `classDef` / theme / `%%{init}%%` unless asked.

3. **Render** from this skill directory (`scripts/mermaid_ascii.py` lives next to this file). Needs `python3` only. Pass `--width` explicitly — the default comes from the terminal size (fallback 80), which is too narrow for most diagrams:

   ```bash
   printf '%s\n' "$SRC" | python3 scripts/mermaid_ascii.py --width 160
   # file: python3 scripts/mermaid_ascii.py --width 160 diagram.mmd
   ```

4. **Output** renderer stdout in a fenced code block. Optional one-line caption. If the output is a `╭ mermaid: <type> ─` box echoing the source (plus a `too wide` hint), it did not render: raise `--width` (160 → 200 → 240) and re-run, and shorten participant/message labels if it still echoes. Never hand-draw.

**Done when:** allowed type chosen, render command succeeded, and the reply contains that ASCII (not unrendered Mermaid alone).

## Type selection

```
time-ordered messages?  → sequenceDiagram
entity relationships?   → erDiagram
type/module structure?  → classDiagram
states + transitions?   → stateDiagram-v2
else process/arch       → flowchart TD|LR
```
