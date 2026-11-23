# Residue patterns

Numbered residue patterns with a Before and an After. Read the entry you are working on; the numbers are stable.

Each Before shows residue; each After shows the same artifact with the residue gone. An After is an illustration, not a template to copy.

Before applying a generalization, check the artifact class in `SKILL.md`. In a one-off deliverable the identifiers stay; in a reusable template they are replaced or dropped.

## R1 Request echo

Before: `As requested, this guide uses only built-in tools. Based on your instruction, the examples use Python 3.11.`

After: `The examples use Python 3.11.`

State the fact; drop the fact that someone asked for it.

## R2 Avoided alternatives and diff-anchored writing

Before: `Unlike the previous version, this script does not shell out to Git. We will not use Homebrew here.`

After: `The script does not shell out to Git. Homebrew is not used.`

Describe the thing, not the change. In a changelog, a migration guide, or a pull request body, describing what changed is the artifact's subject, and this pattern does not fire. It fires where the reader meets the artifact fresh.

## R3 Conversation reference

Before: `The user wanted a short overview, so this document is brief. The prompt says to avoid jargon.`

After: delete the paragraph. The document is already brief, and the jargon is already gone.

## R4 Assumption disclosure

Before: `This document assumes the reader is already on the 2.x line. Because of the constraint on setup time, installation is out of scope.`

After: `Written for readers on the 2.x line. Installation is out of scope.`

A scope statement belongs in the artifact. The reason someone set that scope does not.

## R5 Tool disclosure

Before: `No Git, Homebrew, or additional CLI tools are used. This was changed to use Google Drive.`

After: `Share the project folder with Google Drive.`

## R6 Change justification

Before: `This section was added because the reviewer asked about rollback. To satisfy the requirement, the table below lists every flag.`

After: `The table below lists every flag.`

When the reader does need a reason, give a technical one. A process one is residue.

## R7 Session identifiers

Before, in a reusable skill: `Run scripts/detect.py on the file; the FeatureStore benchmark needed this.`

After: `Run scripts/detect.py on the file.`

Issue numbers, ticket keys, internal project names, and file names that exist nowhere else belong to the session, not to the artifact.

## R8 Case measurements

Before: `Cutting the file from 812 lines to 402 removed 63% of the content.`

After: `The file is 402 lines.`

A size or count of this particular change is a record of the work. Keep it only when the artifact is a report about that work.

## R9 In-group vocabulary

Before: `Fix the round-3 issue before merging.`

After: `Fix the issue before merging.`

Terms that only make sense inside this deliverable, or inside this conversation, do not survive into the final text.

## R10 Comment that justifies an expectation

Before:

```python
# the reviewer asked for an explicit check here, so callers can skip validation
```

After: delete the comment, or keep only the fact a reader cannot derive from the code:

```python
# callers can skip validation
```

## R11 Per-file introduction the reader does not need

Before:

```go
// This file contains the helpers used by the import pipeline.
// It was split out of importer.go during the cleanup pass.
```

After:

```go
// Helpers for the import pipeline.
```

## R12 Verification-status or scope disclaimer in shipped tooling

Before: `# NOTE: this path is untested against Windows.`

After: fix the gap, or track it where the team tracks work.

Keep the disclaimer when the reader genuinely needs to know the limitation. A limitation the user must plan around is user-facing content, not residue.

## R13 Annotation that restates the line

Before:

```python
count += 1  # increment the counter
```

After:

```python
count += 1
```

## R14 Template residue

Before: `Do not add extra examples to this list. Note: keep the steps short.`

After: `Keep the steps short.`

Corrective instructions taken from the session, and rules that say the same thing twice, are both residue. State the rule once.

## R15 Patchwork register

Before: a formal opening paragraph, bullets carried over from a later round of feedback, and a closing `Let me know if anything is unclear.`

After: one register throughout, and the closing offer removed.

Signs that several rounds of instruction shaped the text, rather than one author, count as residue even when every sentence is clean on its own.

## R16 Example that became the topic

Before, in a reusable guide: `Run the migration on payments, then auth, then search.`

After: `Run the migration on service A, then service B, then service C.`

The three service names came from the case that motivated the guide. Keep them when the artifact is a runbook for those services; use clearly synthetic identifiers when the artifact teaches the pattern. Preserve the original sequence without inventing a sorting criterion.
