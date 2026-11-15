---
name: grill-me
description: Use when asked to stress-test a plan or design through an interview.
disable-model-invocation: true
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Word each question so "yes" accepts your recommended answer.

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent with a fresh context window to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.

## Question tool

Use `ask_user_question` to present interview rounds when available. Batch independent questions in one call, up to four questions. If the frontier is larger, use successive rounds without asking dependent questions early. Give each question two to four concrete options; put the recommended option first and append `(Recommended)` to its label. Use the upstream Markdown round format when the tool is unavailable.

## Execution controls

When the frontier is empty, confirm that you and the user have reached a shared understanding. Then present:

`Confirm: proceed with implementation? (run / run-verify / no / revise / show)`

Do not implement until the user says `run` or `run-verify`.

### Run

On **run**, implement the design established by the interview. Preserve the confirmed decisions and scope; do not reopen resolved questions.

### Run-verify

On **run-verify**, do the same as **run**, then launch an independent subagent to verify before the completion report.

Subagent verify rules:
- Use a general-purpose subagent unless a specific verify/review subagent clearly fits.
- Give the subagent the confirmed decisions and scope, actual changed-file scope, and checks already performed.
- Verify the implementation against the confirmed decisions, scope, acceptance criteria, and validation plan established during the interview.
- Inspect the real diff and relevant files, not the implementer summary only.
- Run feasible checks and report evidence for each requirement.
- The implementer waits for the subagent result, then reports pass/fail.
- If verification fails, summarize the findings, fix them, and rerun independent subagent verification.
- Repeat the fix-and-verify loop until the subagent passes or a real blocker prevents completion.
- The implementer cannot accept its own work without a passing independent subagent result.

### Revise

On **revise**, resume the interview to incorporate the requested changes. Recompute the frontier and ask the next round of questions.

### No

On **no**, stop without implementing.

### Show

On **show**, render the confirmed design as an ASCII architecture diagram:

1. Use box-drawing characters (`─`, `│`, `┌`, `┐`, `└`, `┘`, `├`, `┤`, `┬`, `┴`, `┼`) for components, data flow, relationships, and layers.
2. Show a bird's-eye view of the final design, not the discussion process.
3. Re-prompt: `Confirm: proceed with implementation? (run / run-verify / no / revise / show)`
