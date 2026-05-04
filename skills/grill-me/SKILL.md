---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, using the `question` tool if available. When providing options, mark the recommended one with "(Recommended)" so the user has a clear reference.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Closing phase

When all branches are resolved and no further questions remain, produce a final summary in this format:

```markdown
## Design Summary

### Decisions Made
- <Decision>: <chosen answer> — <one-line rationale>

### Scope
- <What this plan covers>
- <What is explicitly out of scope>

Confirm: proceed with implementation? (yes / no / revise)
```

Do not begin implementation until the user explicitly confirms "yes".
