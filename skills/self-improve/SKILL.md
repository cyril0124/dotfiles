---
name: self-improve
description: Extract behavior-improvement rules from the current conversation. Use when the user invokes self-improve.
---

# Self Improve

Review the current conversation and convert it into concrete rules for improving future agent behavior.

## Scope

- Analyze only the current conversation context.
- Do not read external logs, historical sessions, `AGENTS.md`, memory files, or git diffs unless explicitly requested.
- Do not write files or update persistent memory.
- Output rules and suggestions only.
- Include a copy-ready `AGENTS.md` suggestion when a lesson is worth turning into a persistent agent rule.

## Rule Standard

Include a rule when it is useful for future behavior. Rules may come from mistakes, user preferences, or positive patterns.

Prefer practical rules over postmortem detail:

- Good: "When the user says 'revise', do not implement; ask what should change and restate the updated design."
- Bad: "Be more careful."

## Workflow

1. Identify moments where the user corrected, redirected, approved, or rejected behavior.
2. Extract user preferences from explicit choices and repeated signals.
3. Identify positive patterns that worked well and should be repeated.
4. Convert observations into concise rule entries.
5. End with a short checklist for the next similar session.

## Evidence

- Keep evidence lightweight: briefly mention the visible session event behind the rule.
- Do not require verbatim quotes unless wording matters.
- Do not infer hidden intent.
- If there are no useful rules, say so plainly.

## Output Language

- Match the language the user is using in the current request.

## Output Format

````markdown
## Self-Improve Notes

### Behavior Rules
- <rule>  
  Evidence: <brief session event>

### User Preferences Learned
- <preference>  
  Evidence: <brief session event>

### Positive Patterns
- <pattern to reuse>  
  Evidence: <brief session event>

### Next-Session Checklist
- <short action item>

### Suggested AGENTS.md Addition
```markdown
<copy-ready rule or "None">
```
````

## Example

````markdown
## Self-Improve Notes

### Behavior Rules
- When a user says `revise`, treat it as design feedback, not implementation approval.  
  Evidence: The user approved the name change direction but then clarified that the content also needed improvement.

### User Preferences Learned
- The user prefers command-like skills with concise trigger descriptions when they expect manual invocation.  
  Evidence: The user chose a short/manual trigger style.

### Positive Patterns
- Use focused option questions to quickly converge naming and scope decisions.  
  Evidence: The design moved from `session-insights` to `self-improve` after targeted choices.

### Next-Session Checklist
- Check whether the user wants a rename only or a content rewrite.
- Preserve manual-trigger descriptions unless the user asks for automatic triggering.

### Suggested AGENTS.md Addition
```markdown
- When the user asks for a skill intended for manual invocation, keep the skill description concise and trigger-oriented instead of broadening automatic trigger conditions.
```
````
