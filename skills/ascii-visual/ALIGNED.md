# Aligned Mode — Python-Generated Diagrams

## When to Use

- Output embedded in files (README, docs)
- CJK or variable-width text nearby
- Many columns that must align precisely
- User requests "aligned" / "对齐"

## Convention

```
┌──────────────────────────────────────────────────────────────────┐  68 chars
│  content (66 chars between outer │ markers)                      │
└──────────────────────────────────────────────────────────────────┘
```

- **Outer box**: `┌` + 66×`─` + `┐` = 68 chars total
- **Content**: `│` + 66 chars + `│` = 68 chars total
- **Inner box**: indented 2 spaces, max 60 chars content

## Script Template

```python
W = 66  # width between outer │ markers

def tl(text):
    """┌─ title ──────────────────────────────────────────────────────┐"""
    L, p, r = "  ┌─", " " + text + " ", "┐ "
    d = W - 4 - len(p) - 2
    if d < 0: p = " " + text[:len(text)+d] + " "; d = W - 4 - len(p) - 2
    return L + p + "─" * max(0, d) + r

def sl(text):
    """├─ title ──────────────────────────────────────────────────────┤"""
    L, p, r = "  ├─", " " + text + " ", "┤ "
    d = W - 4 - len(p) - 2
    if d < 0: p = " " + text[:len(text)+d] + " "; d = W - 4 - len(p) - 2
    return L + p + "─" * max(0, d) + r

def cl(text):
    """│ content                                                      │"""
    L, R = "  │ ", "│ "
    mx = W - 4 - 2
    if len(text) > mx: text = text[:mx]
    return L + text.ljust(mx) + R

def csl(lt, rt, split=37):
    """│ left          │ right                                        │"""
    L, M, R = "  │ ", " │ ", "│ "
    lf = split - 4 - len(lt)
    if lf < 0: lt = lt[:len(lt)+lf]; lf = 0
    rf = W - split - 3 - len(rt) - 2
    if rf < 0: rt = rt[:len(rt)+rf]; rf = 0
    return L + lt + " " * lf + M + rt + " " * rf + R

def ol(text):
    """Outer content line padded to W chars"""
    if len(text) > W: text = text[:W]
    return text.ljust(W)

IB = "─" * (W - 5)  # inner box bottom dashes
```

## Workflow

1. Copy template into a Python script
2. Build lines: `d = []`
3. Outer top: `d.append("┌" + "─" * W + "┐")`
4. Content: `d.append("│" + ol("  text") + "│")`
5. Separator: `d.append("├" + "─" * W + "┤")`
6. Inner sections: use `tl`, `sl`, `cl`, `csl`
7. Inner bottom: `d.append("│" + ol("  └" + IB + "┘") + "│")`
8. Outer bottom: `d.append("└" + "─" * W + "┘")`
9. **Verify**: `assert all(len(l) == 68 for l in d), f"Bad line: {[l for l in d if len(l)!=68]}"`
10. Print and write to file

## Key Constraints

- No CJK/emoji inside code blocks — they break `len()` alignment
- All lines **exactly** 68 chars — assert before writing
- Box-drawing chars (`─│┌┐└┘├┤┬┴`) are single-width, safe to use
