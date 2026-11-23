---
name: sanitize-artifacts
description: Use for standalone delivery or prompt, conversation, and session leakage checks. Covers documents, reports, code comments, commit messages, pull request text, skills, and configuration. Remove production residue, session-specific identifiers, and meta-commentary; preserve load-bearing content; update staged, committed, or pushed records.
---

# sanitize-artifacts

## Artifact classes

| Class | Examples | Identifiers |
|---|---|---|
| One-off deliverable | design doc, runbook, README, pull request body | real names, paths, commands |
| Reusable template | skill, guide, checklist, starter config | synthetic instance, or drop the example and state the rule |
| Report about this work | status report, postmortem, review notes | numbers and paths the report conveys |

Residue is deleted in every class; each class keeps what the reader needs: system detail, work facts, or the generalized pattern. Unclear or mixed → one-off deliverable. Templates stay as short as purpose allows; one-off deliverables keep needed detail.

## Residue

Read the whole artifact, untouched lines included. Production context is input, not content; each statement is audience content (appears directly), production guidance (shapes structure, tone, scope, examples, naming), or residue (delete).

Residue echoes the request, instruction, prior version, avoided alternative, or constraint reason: `as requested`, `based on your instruction`, `we will not use`, `unlike the previous version`, `the user wanted`, `this was changed to`. Judge contextually; keep what the audience needs; pairs: [references/residue-patterns.md](references/residue-patterns.md).

Reusable artifacts: generalize conversation-derived specifics even when useful — issue, ticket, case and pull request numbers, work-only names, page citations, change counts, measurements, local vocabulary. Examples show patterns, not the motivating case. Sweep the whole artifact, earlier commits included.

## Must survive

Delete residue without changing substance. Assertions, attribution, and quantity never move:

- Measurement vs claim: `weighs 23.2 lb` is observation, `claimed weight` is attribution; never add or strip claimed, reportedly, allegedly.
- Hedges: `risk of over-diagnosis` minus `risk of` asserts occurrence; remove stacked hedges one at a time, never the last.
- Judgment: `more of a deterrent than real theft prevention` is a complaint; never invert it.
- Binding: `30-hour battery life` is not `30 hours of noise cancellation`; keep figure-to-noun in headings, captions.
- Relationships: ranking, order, timing, negation; `both jobs run at once` is not sequential.
- Placeholders: `[Name]`, `{{first_name}}`, `[Your Company]` verbatim.

Keep paths, commands, API and symbol names, environment variables, config keys, error strings, versions, dates, citations, quoted evidence.

Reusable examples: case identifiers become synthetic names or placeholders, or the example goes; keep behavior, relationships, commands, interfaces. May paraphrase filler adverbs, connectives, passive verbs, abstract nouns that keep the domain term.

Never invent names, paths, dates, statistics, quotations, citations, dependencies, ordering, except synthetic identifiers. Missing detail → keep the general statement; rewrite existing content only.

## Code and non-text residue

Source residue: comments justifying an expectation through design internals, per-file introductions, verification or scope disclaimers in shipped tooling, annotations restating code. Keep a comment only for what the code cannot show. Skills and templates address agents, so session corrections, duplicate rules, and drafting-only phrasing are residue too.

Build outputs: separate embedded debug paths from runtime dependencies before replacing; keep required paths. Logs: keep the original record, ship a sanitized copy alongside. Machine identifiers: remove the environment-specific constant, not the surrounding passage.

## Constraints are usually invisible

Apply constraints through design, never by announcement.

| Constraint | Applied as |
|---|---|
| Avoid advanced terms | simpler wording throughout |
| Avoid CLI black boxes | clear, concrete steps |
| Google Drive, not Git | Drive-based workflow |
| Beginner-friendly | pacing, definitions, worked examples |
| Do not mention X | X omitted, omission not announced |

State a constraint only when the audience cannot proceed without it; describe artifact properties, not imposed rules. Conversation examples set abstraction level, audience, tone; copy one only when the artifact needs it, never as the topic.

## Token sweep

Sweep after the rewrite and the record update, at most two rounds.

```bash
scripts/token-sweep.sh report.md FeatureStore 1729 "round 3"
scripts/token-sweep.sh report.md --tokens-file /tmp/session-tokens.txt
```

The script resolves from the skill directory. Exit 0 = current versions clean, 1 = hits, 2 = bad arguments. Tokens file: one token per line, blanks skipped, all else literal. Hits print `SOURCE PATH:LINE: [TOKEN] CONTENT`. Current versions = disk plus the `staged` index, unchanged lines included, deleted diff lines excluded; `HEAD` is informational.

1. List tokens: identifiers, numbers, paths, names, counts, quotations.
2. Sweep; classify worktree and staged hits, inspect `HEAD` for records to update.
3. Fix residue, keep needed content, explain retained tokens in one line after the artifact.

Stop when current-version hits are resolved or explicitly retained; report unresolved hits at the limit.

## Staged, committed, or pushed artifacts

Edit, re-stage or amend, or update the pull request body; verify the record carries the revision and the behavior survives. Change history only when authorized; never force-push or rewrite shared history unasked. Check other conversations, repositories, and sent attachments before calling a leak closed: local cleanup proves nothing about them; out of reach → disclose in one line.

## Language polish

Drop chatbot phrases and patchwork phrasing; keep natural language, intended voice, necessary terms. Chinese artifacts also follow [Chinese style](references/chinese-style.md).

## When not to run

User-authored prose in the author's voice; verbatim quotes, captured evidence, logs, third-party text; unnamed files; required disclosures — AI-use statements, provenance, audience-entitled attribution.

## Scope

Never conceal production from entitled reviewers, defeat academic-integrity or hiring checks, or remove security or compliance evidence. A request implying that goal → explain and stop.

## Output rules

Verify standalone readability, preserved meaning, consistent tone and terminology, clean token sweep. Output the revised artifact itself, no process preface ("I removed the meta instructions", "Here is the sanitized version"); a brief label only when clarity needs one. Artifact plus change summary → artifact first, summary after.

Three exceptions, one line each: retained token and its reason, unresolved issue after two rounds, requested report, diff, or style choice.
