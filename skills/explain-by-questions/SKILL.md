---
name: explain-by-questions
description: Explain a concept in a fixed, bullet-first format with numbered, traced references.
disable-model-invocation: true
---

# Explain by questions

Bullet-first: one-line answer, three labelled bullet sections, each citing the numbered sources it drew from. A reader skimming only the bullets still gets the concept, and sees where every claim came from. Questions drive reasoning inside bullets, never structure. Research, drafting, stress-testing: before writing, never inside the answer.

## Before writing

**Research until three things are supported**: why it exists, how it works, where it stops.

- Behavior, versions, numbers, defaults, limits: find the source stating them.
- Code: read the source, cite `path:line`, not a blog post.
- Record what each source proves. Three to five sources usually covers claims.
- Every factual claim needs evidence. Reasoning + opinion are not evidence. Never invent a citation, URL, path, or line number.
- Unverifiable claim → mark unverified + smallest check that settles it.
- Rank candidates by who owns the claim: see Sources.

**Draft + attack first**: concept in one concrete sentence; what happens without it; mechanism; cost; three or four bullets per section; whether the name earns a section. Then sharpest one or two doubts: holds without leaning on the term? mechanism or conclusion repeated? predicts what that is false? which real case breaks it? Revise max three rounds.

## Format

```
# <the concept, no question mark>
<one-line answer: what it is, plain>

## Where the name comes from
Why is it called X?
- <what the name points at, and the word's role in the sources>
- <the part of the name that misleads, and the mechanism it hides>

references: 1, 3

## Why it exists
- <bullet>
- <bullet>

references: 1, 2

## How it works
- <bullet>
- <bullet>
  * <sub-bullet, only when the parent has parts>

references: 2, 4

## Where it stops
- <bullet>

references: 4

## All references
- (1) measured · [<title>](<URL>) · <claim, as the source states it>
- (2) inferred · [<title>](<URL>) · <claim, plus why it follows rather than being stated>
- (3) unverified · <claim> · <smallest check that settles it>
```

Three content sections, in that order. At most two extras: `## Where the name comes from` directly after the one-line answer; `## How it differs from X`, `## What follows from it` and the like after `## Where it stops`. One H1, one H2 per section, nothing deeper.

Titles:

- H1 = the concept name only. No question mark, label, or number.
- H2 = a content label saying what the section holds, six words max. Never a question, never numbered.
- Vague labels are defects: "overview", "more info", "notes", "key points".

Sections:

- Bullets are the body. Three to six per content section. No bullets = defect.
- Lead line before the bullets optional, two sentences max, never repeating the bullets.
- One sentence per bullet. Two sentences → two bullets, or nest the second.
- Nesting: one level max, three sub-bullets per parent, only when the parent has parts.
- Ordered lists only for steps whose order changes the outcome; else plain bullets.
- One-line answer under the H1 stands alone, no numbers, versions, or limits: those belong in a cited section.
- Body under ~300 words, fifteen bullets max including sub-bullets.

Style:

- One analogy max, optional, in the lead line or the bullet it clarifies. No second metaphor.
- Three unfamiliar terms max, each defined at first appearance. Bold only a term's first definition.
- Language: every user-facing word, headings and citation labels included, in the user's language. Structure unchanged by language.

Name section:

- Default to including it. Skip only when the name is a plain description of the mechanism (rate limiting, connection pool, read timeout) and the origin adds nothing.
- H2 stays a content label; the question opens the section as the lead line, bullets answer it.
- One to three bullets: what the name points at + why that word was chosen; then the misleading part + the mechanism it hides.
- Origin bullets carry a ladder rung:
  1. A source states the naming or defines the term in context → `measured`.
  2. No source records the naming decision, but the sources use the word consistently for one role → `inferred`: name the usage, say the decision is unrecorded.
  3. Nothing supports it → `unverified`: origin undocumented in the opened sources + the check that settles it (original spec, design paper, committee notes).
- Never infer an origin from how the name sounds. Never write folk etymology.
- Name the term the reader will meet in the sources, even in a non-English answer.

Citations:

- Number reference items `(1)`, `(2)`, `(3)` upward, in order of first citation.
- Close every content section with the IDs it drew from, ascending, comma-separated, own line: `references: 1, 3`. Scenario- or reasoning-only section: `references: none`.
- Every bullet carrying a fact, number, version, limit, or behaviour is covered by an ID in its section's line. Nothing behind it → source it or cut it.
- Section citing three or more items, bullet source ambiguous → single ID at the bullet's end: `- Shared storage keeps one budget (2)`.
- Scenario premises are not claims: an invented example needs no ID, a statement about the world or the system does.
- Item cited by no section → cut. Every item reachable from the body.
- Citation line is a line, not a bullet, and does not count toward the bullet budget.

Sources:

- Cite the source owning the claim: standard, spec, RFC, the project's own docs for that project's terms, source code, the paper that proposed it.
- A note, checklist, or summary tells you what to verify, never what is true. A claim resting only on one is `unverified`; its check is the owning source.
- Never cite the user's own files, this conversation, another agent's answer, aggregator or wiki pages, or a third-party tutorial. A vendor's own engineering blog is a primary statement of its design.
- A wiki or aggregator page may locate the original, never serve as the citation.
- One source per claim family, no stacked links.
- Cite the version actually opened: `<spec>.pdf:924`, `README.md#L63`, `path:line`.
- Sources disagree → keep the disagreement, never merge into false certainty.

All references:

- One bucket per item: `measured` (owning source states it), `inferred` (follows from the owning source, not stated), `unverified` (no owning source). Never merge or relabel buckets. Never show a bucket in the body.
- An `inferred` claim reads as an inference in the body too ("this implies"), never as flat fact.
- Claim failing traceability → downgraded to `unverified` or cut, never left standing.
- External sources as markdown links, `[title](URL)`, not bare URLs. Local files as `path:line`. Commands as the command + key output.
- Only sources opened while preparing this answer. A remembered URL is not a source.
- An empty search is no signal, not evidence of absence. Write "nothing found", not "there is none".
- Contradictions listed, not silently resolved, both sides tagged.

Not allowed: tables; emoji; code unless requested; documentation or support-agent voice; filler such as "it is important to note" or "in conclusion".

## Example

Example request: what is rate limiting?

````markdown
# Rate limiting

A service caps how many requests one client may make in a window, so one runaway client cannot take
the whole system down with it.

## Why it exists

- A client sends two hundred requests a second
- The connection pool fills instantly, and every other request slows down with it
- The outage is not caused, it is amplified

references: none

## How it works

- The entry point counts requests per identity, then rejects or queues whatever passes the threshold
- The counter lives in shared storage near that entry, so every machine spends one budget
  * It is the bouncer counting heads at a club door: entry is not blocked, the room is kept from
    packing so tight that nobody can move
- Steps per request:
  1. Read the counter for the client's key
  2. Under the threshold: serve the request, increment the counter
  3. At the threshold: return 429, or queue the request

references: 1, 2

## Where it stops

- Thresholds are hard to tune: loose and nothing is blocked, tight and ordinary traffic takes the hit
- It stops one runaway client, not everyone slowing down at once
- A per-client limit does not answer a total load problem; that is a queue or capacity decision (2)

references: 2, 3

## All references

- (1) measured · [RFC 6585](https://www.rfc-editor.org/rfc/rfc6585) · a rejected request receives the
  429 status code
- (2) inferred · [Cloudflare, "Counting things"](https://blog.cloudflare.com/counting-things-a-lot-of-different-things/)
  · a shared counter design; the post supports one budget per machine rather than stating it
- (3) unverified · the default thresholds of a specific gateway are plan-specific · the gateway's own
  configuration reference settles it
````

`Rate limiting` is a plain description of the mechanism, so this answer skips the name section.

## When the reader replies

- **Follow-up question**: answer it, or add a bullet to the section it belongs to.
- **Too long**: cut to the H1, the one-line answer, `## Where it stops`.
- **A section was unclear**: rewrite that section's bullets only.
- **Something is wrong**: name the step where the reasoning stops working, give the corrected version, retag affected reference items.
- **Silent**: nothing to do. The answer never waits for a reply.

## Other cases

- Direct answer, steps, fixes, debugging: give it plainly, skip this format.
- No source reachable: say so in the section's citation line and in All references, mark those claims unverified, name the smallest check.
- Still confused: add one worked step to `## How it works`. Never a new analogy.

## Check before sending

1. H1 = the concept only; each H2 a content label of six words or fewer, never a question, nothing deeper?
2. One-line answer standing alone, without numbers, versions, or limits?
3. Three content sections in that order, at most two extras, the name section present unless the name is a plain description?
4. Each content section three to six bullets, one sentence per bullet, at most one nesting level, at most fifteen bullets and ~300 words in the body?
5. Each content section closed by an ascending `references:` line, `none` when nothing is sourced, every fact and every ID accounted for on both sides?
6. Every source opened this turn and admissible, external ones as markdown links, one source per claim, one bucket per item, no bucket in the body?
7. Headings, body, and citation labels in the language the user wrote in?
