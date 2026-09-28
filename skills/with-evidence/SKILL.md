---
name: with-evidence
description: Use when the user explicitly requests evidence-backed claims.
---

# With Evidence

Answer with evidence for this response only. Do not persist this mode into later turns unless the user triggers it again.

## Evidence Rules

- Support factual claims with verifiable evidence from local files, command output, web/docs, or other tool-observed sources. Use tools to gather it when available and relevant.
- Do not treat model reasoning, guesses, or unstated assumptions as evidence, and keep opinions, recommendations, and tradeoffs separate from verified facts.
- Trace each claim to the source that owns it: the file, doc, spec, command, or dataset that states it. Summaries, aggregators, and other agents' answers own nothing.
- Tag every evidence bullet with exactly one bucket, defined under Output Format below. Never merge or relabel buckets, and keep the bucket words out of the prose.
- A claim that cannot be traced is downgraded to unverified or cut. Never leave it standing as fact.
- An empty search is no signal, not evidence of absence: write "nothing found", not "there is none".
- When sources contradict each other, list both, each tagged, rather than silently picking one.
- Do not fabricate citations, paths, commands, URLs, or line numbers.

## Output Format

Write the answer normally, then add an `Evidence` section when factual claims need support.

```markdown
**Evidence**
- measured — `path/to/file:line` — the claim, as the source states it.
- inferred — `command ...` — the observed output, and the claim it implies rather than states.
- unverified — <claim> — what is missing, and the smallest check that would settle it.
```

Every bullet opens with one bucket:

- `measured` — the source states it. Quote or paraphrase the source closely.
- `inferred` — it follows from the source but is not stated there. Name the observation it follows from, and write the claim as an inference in the prose too ("this implies"), never as fact.
- `unverified` — no source supports it. State what is missing, plus the smallest check that would settle it.

Order the bullets by bucket when that reads better; keep one bullet per claim and one source per bullet.

## Local Evidence

- Prefer `path:line` for files when line numbers are available.
- For commands, name the command and summarize the relevant output instead of pasting noisy logs.
- For tests or builds, include pass/fail status and the exact command.

## External Evidence

- Prefer official documentation, source repositories, standards, papers, or primary sources.
- Include enough source identity for the user to find it: title, URL, or repository path.
- Open the source before citing it. A remembered URL is not evidence.
- If web access is unavailable or not used, mark external claims as unverified instead of guessing.

## When Evidence Is Missing

If the best answer depends on facts not yet verified, say so explicitly, using the same three buckets:

- measured: facts backed by a source.
- inferred: what follows from those facts but is not stated by them.
- unverified: assumptions without support, each with the smallest check that would settle it.
