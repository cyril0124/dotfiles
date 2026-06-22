---
name: with-evidence
description: Require evidence-backed answers for the current response. Use when the user says "with-evidence" or "evidence" and wants claims supported by verifiable local files, command output, or external documentation.
---

# With Evidence

Answer with evidence for this response only. Do not persist this mode into later turns unless the user triggers it again.

## Evidence Rules

- Support factual claims with verifiable evidence from local files, command output, web/docs, or other tool-observed sources.
- Do not treat model reasoning, guesses, or unstated assumptions as evidence.
- Use tools to gather evidence when available and relevant; if evidence cannot be obtained, label that part as unverified.
- Keep opinions, recommendations, and tradeoffs separate from verified facts.
- Do not fabricate citations, paths, commands, URLs, or line numbers.

## Output Format

Write the answer normally, then add an `Evidence` section when factual claims need support.

```markdown
**Evidence**
- `path/to/file:line` — what this proves.
- `command ...` — key observed output/result.
- <source title or URL> — what this proves.
- Unverified: <claim or assumption> — <why evidence is missing or how to verify>.
```

## Local Evidence

- Prefer `path:line` for files when line numbers are available.
- For commands, name the command and summarize the relevant output instead of pasting noisy logs.
- For tests or builds, include pass/fail status and the exact command.

## External Evidence

- Prefer official documentation, source repositories, standards, papers, or primary sources.
- Include enough source identity for the user to find it: title, URL, or repository path.
- If web access is unavailable or not used, mark external claims as unverified instead of guessing.

## When Evidence Is Missing

If the best answer depends on facts not yet verified, say so explicitly:

- Verified: facts backed by evidence.
- Unverified: assumptions or plausible explanations without evidence.
- Verify next: the smallest command, file, or source needed to confirm it.
