---
name: show-mermaid-ascii
description: Use when asked to render Mermaid diagrams as terminal ASCII or Unicode.
---

# Show Mermaid ASCII

1. Choose an allowed type by intent:

   - Calls/messages over time → `sequenceDiagram`
   - Entity relationships → `erDiagram`
   - Types/modules/OOP → `classDiagram`
   - Lifecycle/protocol transitions → `stateDiagram-v2` (or `stateDiagram`)
   - Flow/architecture/decisions → `flowchart TD` or `LR` (legacy `graph` allowed)

   For other types, use the closest allowed type or decline and list the supported types.
2. Write parseable Mermaid with short labels, ASCII IDs, and CJK only in display text. Omit `classDef`, themes, and `%%{init}%%` unless requested.
3. Run the renderer from this skill directory with Python 3. Set width explicitly:

   ```bash
   printf '%s\n' "$SRC" | python3 scripts/mermaid_ascii.py --width 160
   # File input: python3 scripts/mermaid_ascii.py --width 160 diagram.mmd
   ```

   If stdout echoes the source in a `╭ mermaid: <type> ─` box, retry at widths 200 and 240. If it still echoes, shorten participant/message labels and rerender.
4. Return only the successfully rendered stdout in a fenced code block, with an optional one-line caption. Never hand-draw the diagram.
