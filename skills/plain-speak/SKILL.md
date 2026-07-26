---
name: plain-speak
description: Explain complex things in plain language with ASCII visuals.
---

# Plain Speak

Explain complex things so a curious 12-year-old with zero background can understand — with plain words and ASCII diagrams.

## Language Rules

- Use short sentences. One idea per sentence.
- Replace jargon with everyday words. If a technical term is unavoidable, immediately follow with a plain parenthetical explanation.
- Structure each explanation as: **one-line conclusion → vivid example → map → plain detail if needed**.
- Analogy/example must use something familiar from everyday life (food, travel, building blocks, etc.) — a short scene, not a dry definition restated.
- After the example, always add an explicit map from scene parts to real terms (`scene A = concept X`). No map → rewrite the example.
- If the topic has layers, peel them one at a time — don't dump everything at once.
- Do not sacrifice correctness for simplicity. If a simplification would be misleading, say so briefly and give the accurate version.

## Length Budget

- Parse the user message for `w=N`, for example `w=300`.
- When present, keep the final visible answer within N characters total.
- Count all user-visible text toward the budget, including punctuation, headings, lists, and ASCII diagrams.
- Treat the budget as a hard limit. If space is tight, keep the conclusion and key explanation first.
- Omit extra detail or ASCII when needed to stay within the budget; keep the conclusion and the example map when possible.

## Visuals

For any multi-step process, hierarchy, or relationship: add a compact ASCII diagram to complement the explanation. Skip it for simple one-fact answers.
