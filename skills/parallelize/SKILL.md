---
name: parallelize
description: 'Use subagents for substantial independent investigations, review lenses, or implementation tasks, or when the user explicitly requests agents, such as sub=N. Batch short searches and known-file reads with direct tools.'
---

# Parallelize

Main owns plan, dispatch, merge, final answer.

## Choose the execution method

- Batch independent known-file reads, targeted searches, help lookups, and small local edits with direct tools.
- Use subagents when at least two substantial independent slices each require multi-step exploration or reasoning and have a distinct deliverable.
- Explicit user requests for agents override the workload threshold. Keep assignments independent and cap the count to safe, useful work.

## Workflow

1. If `sub=N` is provided, parse a positive integer; invalid → state the format and stop. Otherwise choose the fewest agents justified by the work.
2. Split only by independent file, subsystem, hypothesis, query, or review lens.
3. If no useful independent assignment exists, handle directly and explain any departure from an explicit agent request.
4. Prompt each agent with scope, permission, success check, output format.
5. Dispatch all agents in one round. If runtime cannot parallelize, report it.
6. Merge: dedupe, resolve conflicts by evidence, synthesize one result.

## Patterns

- Review: correctness / security / performance / tests.
- Search: broad investigations across subsystems or competing hypotheses.
- Debug/build: hypotheses or non-overlapping files.

## Failures

- Too many agents → cap to safe slices; say why.
- Agent fails/timeouts → name it; use completed evidence only.
- Conflicts → prefer paths, commands, logs, repro steps.

## Do Not

- Do not edit same file/shared state from multiple agents.
- Do not create extra assignments to fill an agent count.
- Do not concatenate raw outputs.
- Do not hide failures, missing evidence, or conflicts.
