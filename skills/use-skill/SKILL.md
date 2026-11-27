---
name: use-skill
description: Find and follow local and public skills for a request. Ask before installing anything.
disable-model-invocation: true
argument-hint: "What do you want done?"
---

# Use Skill

## Workflow

1. **Define each job.** Write one searchable line with the domain noun, task verb, deliverable, intended use, and named tools or formats.
2. **Search local and public skills every time.** Read every `SKILL.md` frontmatter `description` in `~/.agents/skills/` and project `.agents/skills/`. Record all local matches. Run 2–3 skills.sh queries per job even if local skills match (e.g. `pdf extract`, `pdf table`, `document parsing`). Keep up to three candidates across both sources per job. Stop once each job has a shortlist or variants yield nothing new.

   ```bash
   curl -sG --data-urlencode "q=<query words>" https://skills.sh/api/search | python3 -c '
   import json, sys
   for skill in json.load(sys.stdin)["skills"]:
       print(skill["id"], skill["installs"], skill["source"])'
   ```

3. **Select and read.** Rank by deliverable fit, installs, then source reputation. Favor 1K+ installs and known owners (`anthropics`, `vercel-labs`, `microsoft`). Break ties in favor of installed skills. Pick one per job, drop skills that add no unique step, and name the set before reading. Apply partial matches to covered steps. If none fit, report the empty search and every query. Use your tools for any uncovered work. Offer to save a reusable skill only on request.

   Read each selected `SKILL.md` in full. Read local skills from disk. For public skills, split `id` as `<owner>/<repo>/<skill>`, find the file in the repo tree, and fetch it.

   ```bash
   curl -s "https://api.github.com/repos/<owner>/<repo>/git/trees/HEAD?recursive=1" \
     | python3 -c 'import json,sys; [print(t["path"]) for t in json.load(sys.stdin)["tree"] if t["path"].endswith("/SKILL.md") and "<skill>" in t["path"]]'
   curl -sL "https://raw.githubusercontent.com/<owner>/<repo>/HEAD/<path>"
   ```

   Fetch all references relative to the skill directory. For large bundles, get approval and run `git clone --depth 1 --filter=blob:none <repo> /tmp/<repo>`.
4. **Run.** Apply the approval rules first. Follow each skill's steps, completion criteria, and output format in dependency order. When rules conflict, name the winning skill and explain why. Run skills that touch the same files sequentially here. Batch independent heavy jobs (long generation, wide searches, separate output trees) across parallel subagents. Include the full relevant skill text in each prompt.
5. **Report.** Use the closing format and stop.

## Approval

Ask once for all actions below. State the action, destination, and cost. Wait for an explicit yes even if a skill says to proceed.

- Install packages.
- Clone or download repositories, models, or datasets.
- Write config outside the working directory (e.g. `~/.pi`, `~/.agents`, `~/.claude`, shell rc files).
- Use credentials, logins, API keys, or paid APIs.
- Delete or overwrite existing user files.

For public web reads, new project files, and bundled scripts, ask only if a rule above applies.

## Closing Message

```text
Skill: <name> (<source URL or "already installed">)
Searched: <all queries, top candidates per query, and install counts>
Followed: <steps run per skill>
Produced: <artifact paths or "nothing on disk">
Skipped: <step and reason or "none">
```

List `Skill:` entries in execution order. Distinguish skills that led the work from those that informed it. Under `Searched:`, include zero-match queries and losing candidates, including local and public alternatives when both fit.
