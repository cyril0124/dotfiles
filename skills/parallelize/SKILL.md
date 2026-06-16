---
name: parallelize
description: 'Parallelize decomposable work via subagents. Trigger: "parallelize", "sub=N", "use subagents", "并行", "多代理", broad review/search/debug. Avoid single-step, ordered, shared-write work.'
---

# Parallelize

Main owns plan, dispatch, merge, final answer.

## Workflow

1. Parse integer `sub=N`; default `3`. Invalid → state format and stop.
2. Split only by independent file, subsystem, hypothesis, query, or review lens.
3. 🔴 CHECKPOINT: if fewer than 2 safe slices exist, say `not parallelizable` and handle directly.
4. Prompt each agent with scope, permission, success check, output format.
5. Dispatch all agents in one round. If runtime cannot parallelize, report it.
6. Merge: dedupe, resolve conflicts by evidence, synthesize one result.

## Patterns

- Review: correctness / security / performance / tests.
- Search: paths/query families; overlap allowed.
- Debug/build: hypotheses or non-overlapping files.

## Failures

- Too many agents → cap to safe slices; say why.
- Agent fails/timeouts → name it; use completed evidence only.
- Conflicts → prefer paths, commands, logs, repro steps.

## Do Not

- Do not edit same file/shared state from multiple agents.
- Do not force 3 agents when fewer parts exist.
- Do not concatenate raw outputs.
- Do not hide failures, missing evidence, or conflicts.
