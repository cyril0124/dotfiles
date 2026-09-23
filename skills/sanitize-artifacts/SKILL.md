---
name: sanitize-artifacts
description: Use when preparing generated artifacts for standalone delivery or checking for prompt and conversation leakage.
---

# sanitize-artifacts

Use this skill when the user asks you to inspect, clean up, sanitize, revise, polish, or quality-check artifacts produced during the current work session.

Artifacts include documents, source code and comments, commit messages, pull request text, skills, configuration, reports, logs, and build outputs.

This skill is especially important when the artifact was produced through iterative prompting, corrective instructions, examples, constraints, or vibe-coding-style collaboration.

## Goal

Revise the artifact so that it stands on its own as a coherent final deliverable.

The artifact must not expose unnecessary traces of:

- the user's prompts
- conversation history
- intermediate reasoning
- implementation constraints
- tool choices
- avoided approaches
- prompt-engineering instructions
- scaffolding used during production
- examples that were provided only to guide intent
- corrective feedback given during the conversation

The final artifact should look like it was intentionally designed for its real audience, not assembled from the conversation that produced it.

## Core Principle

Treat the conversation as production context, not automatically as artifact content.

Before preserving any statement in the artifact, classify it as one of the following:

1. User-facing content that the artifact's audience genuinely needs
2. Production guidance that should influence the artifact but should not be visible
3. Incidental conversation residue that should be removed

Only category 1 appears directly in the artifact. Category 2 is reflected indirectly through structure, tone, scope, assumptions, defaults, examples, naming, or design choices. Category 3 is removed.

## What to Remove or Rewrite

Look for and remove or rewrite content that unnecessarily says or implies:

- "As requested...", "Based on your instruction..."
- "We will not use...", "This avoids...", "Unlike the previous version..."
- "The user wanted...", "The prompt says...", "The conversation so far..."
- "This document assumes...", "Because of the constraint..."
- "No Git/Homebrew/CLI/etc. is used...", "This was changed to..."
- "This section was added because...", "To satisfy the requirement..."

Do not remove such content mechanically. Keep it only when the intended audience genuinely needs to know it.

## Generalize, Do Not Only Delete

Deleting statements about the conversation is not enough. Content that merely originates in it must be generalized, even when it reads as useful concreteness.

Bound to this session, and therefore not allowed in a reusable artifact:

- issue, ticket, case, or pull request numbers
- module, signal, file, or tool names that appear only in this work
- document section and page citations
- counts, sizes, and measurements of this particular change
- vocabulary that only makes sense inside this deliverable

Replace such an instance with a synthesized generic instance of the same pattern, or drop it and state the rule alone. In a reusable artifact an example illustrates the pattern; it does not record the case that motivated it.

Sweep the whole artifact, including lines you did not write this turn. Residue often sits in content committed in an earlier round.

## Code and Comments

Source files carry residue of their own:

- comments justifying the expectation from the design's internals
- a per-file introduction the reader does not need
- verification-status or scope disclaimers inside shipped tooling
- annotations that only restate the neighboring line

Keep a comment only when it explains something the reader cannot derive from the code.

In a skill or template the reader is another agent, so corrective instructions taken from this session, rules that duplicate each other, and phrasing that only made sense while the file was being written are residue as well. Keep such a file as short as its purpose allows.

## Non-Text Artifacts

Handle these by purpose rather than by rewriting:

- Build outputs: a path embedded in a binary may be debug information or a runtime dependency. Decide which before replacing anything, and keep the ones the program needs.
- Logs and captured output: keep the original record for diagnosis and deliver a sanitized copy alongside it.
- Machine-specific identifiers: remove the environment-specific constant, not the passage that mentions it.

Sanitize the artifacts the request names. Deleting residue from an adjacent file the user did not mention is a scope violation, not thoroughness.

## Examples vs. Intent

If the user gave an example to communicate intent, do not copy it into the artifact unless the artifact itself specifically needs it. An example from the conversation is diagnostic material, not final content: use it to infer the desired abstraction level, the audience, the tone, the constraints, and the wording that would look unnatural. Do not let an example accidentally become the topic of the artifact.

## Constraints Are Usually Invisible

User constraints should normally affect the artifact's design, not appear as explicit disclaimers.

Bad:

> This guide does not use Git, Homebrew, or additional CLI tools.

Better:

> Share the project folder using Google Drive.

The better version applies the constraint without exposing it as a production rule.

## Staged, Committed, or Pushed Artifacts

Sanitizing frequently begins after the artifact has already been staged, committed, or pushed. The rewrite stays invisible until the record is updated:

1. Edit the artifact.
2. Re-stage it, amend the commit, or update the pull request body.
3. Confirm the updated record carries no residue and that only prose changed.

Do not force-push or rewrite shared history unless the user asks for it.

## Token Sweep

Verify mechanically instead of only rereading:

1. List the tokens distinctive to this session: identifiers, numbers, paths, names, counts, quotations.
2. Search the artifact for them, staged and committed content included.
3. Fix every hit. Keep a hit only when the artifact genuinely needs it, and disclose that exception in one line after the artifact.

## Inspection Checklist

When sanitizing an artifact, check:

1. Does the artifact read naturally to someone who never saw the conversation?
2. Are there any sentences that explain why the artifact was written this way?
3. Are there any unnecessary mentions of tools, exclusions, constraints, or avoided alternatives?
4. Did a prompt example accidentally become part of the deliverable?
5. Are there signs of patchwork from multiple rounds of feedback?
6. Are tone, terminology, and assumptions consistent throughout?
7. Are headings and notes written for the artifact's audience rather than for the creator?
8. Is any meta-commentary present that belongs only in the production process?
9. Are disclaimers or caveats included only when the audience truly needs them?
10. Does the artifact have a single coherent voice?
11. Does every example read as a generic instance rather than a record of this case?
12. Did the token sweep come back clean, and is the staged, committed, or pushed record updated?

## Revision Strategy

Prefer rewriting over explaining. Do not add a report about what you sanitized unless the user asks for one, apart from the one-line disclosure Token Sweep requires. When editing, preserve the artifact's intended purpose, technical correctness, and necessary user-facing requirements.

Remove production residue by converting it into natural artifact design:

- Convert "Do not use advanced terms" into simpler wording.
- Convert "Avoid CLI black boxes" into clear, concrete steps.
- Convert "Use Google Drive, not Git" into Drive-based workflow instructions.
- Convert "Beginner-friendly" into pacing, definitions, and examples.
- Convert "Do not mention X" into omission of X, not a statement that X is omitted.

## Output Rules

When asked to sanitize an artifact, output the revised artifact itself.

Do not preface the artifact with process commentary such as "I removed the meta instructions." or "Here is the sanitized version."

A brief label is acceptable only if needed for clarity.

If the user asks for both the sanitized artifact and a change summary, put the artifact first and the summary after it.

## Quality Bar

The sanitized artifact should feel intentional, unified, and audience-native.

A reader should not be able to infer the prompting history, internal constraints, or corrective conversation unless those details are genuinely part of the deliverable.