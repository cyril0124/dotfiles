---
name: visual-comment
description: Add ASCII visual diagrams as inline comments directly into source code so the code becomes visually readable. Inserts a file-header overview plus per-function/class and complex-block diagrams using line comments, in place. Use when the user runs /visual-comment, asks to "add ascii comments", "visualize this code with comments", "annotate code with diagrams", or wants annotated source that explains control flow, data flow, state machines, or call relationships.
---

# Visual Comment

Annotate source code with ASCII diagrams as **inline line comments**, so reader grasps code shape without leaving file. Writes diagrams *into* source — not a separate `.md` document.

Self-contained: all char tables, rules, diagram patterns below. No dependency on other skills.

## Quick start

```
/visual-comment src/scheduler.py
/visual-comment the parse() function in lexer.ts
可视化注释 这个文件
```

1. Resolve target from prompt (file, or function/region inside it).
2. Read full target before writing. Never annotate from memory or partial reads.
3. Detect comment prefix for language (`#`, `//`, `--`, `;`, …).
4. Insert diagrams at three layers (below), line comments only.
5. Edit source in place. Re-run safe: see Idempotency.

## Placement: three layers

```
File top ──► one architecture / data-flow OVERVIEW of the whole file
   │
Func/Class ──► control flow · call graph · state machine for that unit
   │
Complex block ──► local data flow / structure layout, inside the body
```

- **File header**: one compact overview of file's modules, data flow, or
  responsibilities. Place after shebang / license / `package` line, before imports.
- **Key function or class**: diagram above its definition showing
  control flow, call relations, or state it manages.
- **Complex block**: small diagram inside body, above dense logic
  (nested loops, branching state transitions, non-obvious data reshaping).

## Density: only where it earns its place

Annotate **complex or non-obvious** code. Skip simple, self-evident.

```
Annotate          Skip
─────────         ─────────
state machines    getters / setters
nested branching  one-line wrappers
data reshaping    trivial loops
call fan-out      self-explanatory names
concurrency       plain CRUD passthrough
```

One high-signal diagram beats many boilerplate. Unit obvious from name + one line
of code: no diagram.

## Comment syntax: line comments only

Embed diagrams using language's **line-comment prefix**, one prefix per line. Never
block comments. Line comments can't leave unterminated block — edit is structurally
safe, no compile check needed.

```
Python / Ruby / Shell / YAML      #
C / C++ / Java / JS / TS / Go     //
Rust / Kotlin / Swift             //
Lua / Haskell / SQL               --
Lisp / Clojure / asm              ;
```

Pick prefix from file's existing style. Match file's existing comment convention.

## Drawing characters

```
Boxes:    ┌─┐ │ └─┘  ├─┤ ┬ ┴ ┼
Heavy:    ┏━┓ ┃ ┗━┛   (emphasis / headers)
Double:   ╔═╗ ║ ╚═╝   (titles / section dividers)
Rounded:  ╭─╮ │ ╰─╯
Arrows:   → ← ↑ ↓  ─>  <─  ──>  v
Blocks:   █ ▓ ░
Tags:     [A]dd [M]od [D]el   !! risk   ** new
```

Rules:
- Monospace, fixed-width. Diagrams under ~76 chars wide (prefix + content).
- Box-drawing chars single-width, safe. Avoid emoji + wide CJK inside boxes —
  break alignment. Use ASCII tags like `[x]`.
- Right-pad labels so columns line up. Verify edges align before writing.
- Max ~3 nesting levels; beyond that readability drops.

## Choosing the diagram type

Pick one shape that best explains *this* code; don't force fixed type.
Modules/layers → architecture boxes. Branching → control-flow tree. Sequential
transforms → data-flow pipeline. Status transitions → state machine. Heavy fan-out
→ call graph. Struct reshaping → structure layout. Producer/consumer → swimlane.
Clocked HDL / signal timing → timing waveform; handshakes + pipelines also use
waveforms. See [PATTERNS.md](PATTERNS.md) for ready-to-adapt example of each.

## Timing waveforms (hardware)

Waveforms stay readable only on a **fixed grid**. Pick cycle width (use 8
columns/cycle), every signal uses it, so clock ticks, edges, bus boundaries align
in every column. Pure 7-bit ASCII only — never overline `‾` (U+203E) or box-drawing
chars in waveforms; they render double-width in CJK locales, shift grid. Levels at
distinct heights (`-` high, `_` low, `~` hi-Z); edges on cycle boundaries only
(`/` rise, `\` fall); clock cycle is `/---\___`. Buses use `< value >` window, `X`
at each change, `x` fill for don't-care. Add `c0 c1 c2 ...` ruler. See
[PATTERNS.md](PATTERNS.md) for verified templates.

## Idempotency (re-run)

Source may already hold diagrams from prior run. Before inserting, read existing
comments, recognize prior visual-comment diagrams (box-drawing blocks in line
comments). Refresh in place, don't stack a second diagram. No duplicates.

## Scope

- In scope: one file (or region within it) named by user.
- Out of scope: directory/batch annotation, separate `.md`, copy file,
  compile/syntax verification, forcing label language or diagram type.
