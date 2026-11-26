---
name: show-mermaid
description: Use when asked for Mermaid diagram source, rather than rendered ASCII or images.
---

# Show Mermaid

Choose an allowed type by intent:

- Calls/messages over time → `sequenceDiagram`
- Entity relationships → `erDiagram`
- Types/modules/OOP → `classDiagram`
- Lifecycle/protocol transitions → `stateDiagram-v2` (or `stateDiagram`)
- Flow/architecture/decisions → `flowchart TD` or `LR` (legacy `graph` allowed)

For other types, use the closest allowed type or decline and list the supported types.

Write parseable Mermaid with short labels, ASCII IDs, and CJK only in display text. Omit `classDef`, themes, and `%%{init}%%` unless requested.

Return each diagram as source in its own fenced `mermaid` block. A short caption is optional. For terminal rendering use `show-mermaid-ascii`, for box art use `ascii-visual`, and for themed SVG use `pretty-mermaid`.
