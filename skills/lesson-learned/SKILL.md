---
name: lesson-learned
description: Generate exactly one evidence-backed, portable lesson from the current conversation and append it to LESSON.md. Trigger when the user invokes `$lesson-learned` or explicitly asks to generate, record, or extract exactly one lesson from the current conversation. Requests to review, explain, or improve this skill itself take priority and must not execute the logging workflow; use self-improve for broad conversation analysis.
---

# Lesson Learned

Extract exactly one reusable lesson from the current conversation.

## Scope

- Use only information visible in the current conversation.
- Do not read historical transcripts, memory files, `AGENTS.md`, or git history to find a lesson.
- Base the lesson on an explicit user correction, decision, failure, validation result, or successful pattern.
- Keep the lesson evidence-backed but context-light: preserve the shape of the decision or mistake, not unnecessary local names.
- Do not invent a lesson when the conversation provides no concrete evidence.

## Workflow

0. Determine the user's intent in priority order.
   - If the user asks to review, explain, or improve `lesson-learned` itself, answer that meta-level request, do not modify `LESSON.md`, and stop this workflow. This rule takes priority even when the request invokes or mentions `$lesson-learned`.
   - Otherwise, continue only when the user invokes `$lesson-learned` or explicitly asks to generate, record, or extract exactly one lesson from the current conversation.
1. Identify two or three candidate events internally when available. Use fewer when the conversation provides fewer; never invent candidates.
2. Rank the candidates in this order, then select the highest-ranked event that can become a reusable rule:
   1. The user's latest explicit correction or stated principle.
   2. A correction repeated or clarified by the user.
   3. A validated success or failure with reusable consequences.
   4. An incidental implementation detail.
3. Convert the selected event into an actionable decision rule rather than a recounting of the event.
4. Remove project names, file names, protocol names, issue IDs, local identifiers, and specific numbers unless they are essential to the rule. Preserve the shape of the mistake, not the incident's proper nouns.
5. Run the portability check:
   - Can a reader apply the lesson in a different repository?
   - Does it describe a decision rule instead of recounting an event?
   - Does its example avoid unnecessary local identifiers?
   - If any answer is no, abstract the lesson one level further and check again.
6. Write exactly one generic but concrete bad/good example that demonstrates the rule.
7. Resolve the Git repository root with `git rev-parse --show-toplevel`, then reply with the lesson and append the identical Markdown to that root's `LESSON.md`.

When no candidate supports a reliable, portable lesson, reply in the user's language that there is not enough current-context evidence to create one. Do not modify `LESSON.md`.

## Output

Keep the fixed headings and labels below. Write the title, description, and example content in the user's language.

````markdown
## Lesson: <concise title>

### Description

<one concise, reusable rule tied to the current-context evidence>

### Example
```
Bad: <a generic but concrete behavior that violates the rule>

Good: <the corresponding generic behavior that applies the rule>
```
````

## Logging

- Resolve the repository root with `git rev-parse --show-toplevel` before reading or writing `LESSON.md`. If resolution fails, report the error and do not write a file.
- If that root's `LESSON.md` does not exist, create it as `# Lessons`, one blank line, then the lesson.
- If it exists, append the lesson after one blank line.
- Never overwrite, rewrite, deduplicate, or add dates to existing entries, except for the correction rule below.
- Append only the lesson Markdown, not explanation around it.

### Correction Rule

If the user's next message directly rejects or corrects the lesson appended during the current conversation:

1. Draft the corrected lesson by running only workflow steps 1-6; do not run step 7 or modify the file yet.
2. Resolve the repository root, then verify that `LESSON.md` ends with the exact lesson block previously appended by this skill in the current conversation.
3. If the tail matches exactly, replace only that final block and reply with the corrected lesson.
4. If the file tail does not match exactly, report the conflict and do not modify the file.

Do not modify older entries or apply this exception to a lesson from an earlier conversation.
