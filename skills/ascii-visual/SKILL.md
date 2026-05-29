---
name: ascii-visual
description: Generate aligned ASCII diagrams for architecture, workflows, file trees, and data visualizations. Use when creating box-drawing diagrams, terminal-rendered layouts, swimlanes, blast radius, or when CJK/emoji alignment is needed. Triggers include "draw diagram", "ASCII diagram", "aligned", "visualize architecture".
---

# ASCII Visual

## Characters

```
Standard:  ┌─┐ │ └─┘  ├─┤ ┬ ┴ ┼
Heavy:     ┏━┓ ┃ ┗━┛  ┣━┫ ┳ ┻ ╋
Double:    ╔═╗ ║ ╚═╝  ╠═╣ ╦ ╩ ╬
Rounded:   ╭─╮ │ ╰─╯
Arrows:    → ← ↑ ↓ ─> <─ ──> <──
Blocks:    █ ▓ ░ ▏▎▍▌▋▊▉
```

| Weight | Use |
|--------|-----|
| Standard `─│` | Normal boxes |
| Heavy `━┃` | Emphasis, headers |
| Double `═║` | Titles, section dividers |

## Rules

1. **Monospace only** — all output must render in fixed-width font
2. **Max 80 chars wide** — terminal compatibility
3. **Max 3 nesting levels** — beyond this, readability degrades
4. **No CJK/emoji in code blocks** — use ASCII placeholders `[_] [^] [X]`
5. **Right-pad labels** to align columns
6. **Annotations**: `!!` risk, `**` new, `[A/M/D]` change type
7. **Alignment check** — before outputting, visually verify that box edges, columns, and connectors are aligned

## Patterns

See [PATTERNS.md](PATTERNS.md) for all diagram types:
architecture, file tree, swimlane, blast radius, timeline, comparison, progress.

## Aligned Mode (Python)

When exact alignment matters (mixed-width chars, tables, complex layouts), generate diagrams via Python. See [ALIGNED.md](ALIGNED.md) for the script template and workflow.

**When to use aligned mode:**
- Output will be embedded in a file (README, doc)
- Content has CJK or variable-width text nearby
- Diagram has many columns that must line up precisely
- User explicitly requests "aligned" / "对齐"
