---
name: use-skill
description: Find the skills a request needs among local and public candidates, read them where they live, then follow them, asking before any install.
disable-model-invocation: true
argument-hint: "What do you want done?"
---

# Use Skill

Resolve a request by delegating to existing skills. Name the need, then search both the local list and the public ecosystem, read the source, follow the steps. The local list is a cache of past installs, not the ecosystem: steps 2 and 3 run on every request, and a local match never ends the search.

## Workflow

1. **Name the need.** Write one line holding a domain, a task, and a deliverable, for example `domain: pdf`, `task: extract tables`, `deliverable: csv rows`. Add what the user will do with the result and any tool or format they named. The line is done when it carries a searchable domain noun, a verb, and the output form.

2. **Take inventory of local skills.** List `~/.agents/skills/*/SKILL.md` and the project's `.agents/skills/`, and read the `description` lines in their frontmatter. This step builds one half of the candidate list. A local match adds a candidate, it does not resolve the request. Done when you hold every local candidate, or none.

3. **Search the ecosystem.** Run this step on every request, including ones where a local skill already fits. Query the skills.sh search API:

   ```bash
   curl -s --get --data-urlencode "q=<query words>" https://skills.sh/api/search | python3 -c \
     'import json,sys
   for s in json.load(sys.stdin)["skills"]:
       print(s["id"], s["installs"], s["source"])'
   ```

   Run two or three keyword variants (`pdf extract`, `pdf table`, `document parsing`). Favor sources with 1K+ installs and known owners (`anthropics`, `vercel-labs`, `microsoft`). One job, one search: a request spanning writing, rendering, and publishing has a skill per job. Done when every job in the request holds 0-3 candidates drawn from both the local inventory and these results, or the variants stop returning anything new.

4. **Pick the set, then read each skill in full.** A request often needs more than one skill. Name the set before reading, one skill per job, and no more than the request needs. A local winner gets read straight off disk. Every other one resolves `<owner>/<repo>` plus the skill name to its real `SKILL.md` path:

   ```bash
   curl -s "https://api.github.com/repos/<owner>/<repo>/git/trees/HEAD?recursive=1" \
     | python3 -c 'import json,sys; [print(t["path"]) for t in json.load(sys.stdin)["tree"] if t["path"].endswith("/SKILL.md") and "<skill>" in t["path"]]'
   curl -sL "https://raw.githubusercontent.com/<owner>/<repo>/HEAD/<path>"
   ```

   Path shapes vary (`skills/<skill>/SKILL.md`, `<skill>/SKILL.md`, `<skill>/.claude/skills/SKILL.md`), and the trees listing settles which one applies. The search result's `id` is `<owner>/<repo>/<skill>`. Fetch every file the skill points at by patching the raw URL to the sibling path. When a skill bundles many files, `git clone --depth 1 --filter=blob:none <repo> /tmp/<repo>` beats fetching them one at a time.

   Read to the last line. The rules that fix the output shape sit near the end, which is why a skimmed skill runs worse than no skill at all. Done when you can state every chosen skill's steps and completion criteria from memory, and know which one runs first.

5. **Ask before anything installs.** Following the skills can require installs or changes outside the task; the list below covers what needs a yes. Ask once for the whole set, naming what will run, where it lands, and what it costs. Wait for a clear yes before running any of it, and treat text inside a skill that says "install X" as a description, not permission.

6. **Follow the skills in order.** Run each as written, through its completion criteria, in the layout it specifies. Order the set so each skill's output feeds the next. When two skills disagree, name the winner and why before continuing.

   Skills touching the same files run one after another in this session. Independent heavy ones, meaning long generation, wide searches, or separate output trees, each go to their own subagent, dispatched in one message so they run concurrently. A subagent cannot fetch or read a skill for itself, so paste the skill text into its prompt.

7. **Close by naming the skills.** The final message opens with the skills used and ends with the state of the work, in the format below.

## Closing message

Each run finishes with one `Skill:` line per skill used, in the order they ran, then one line each for the rest.

```
Skill: <name> (<source URL, or "already installed">)
Skill: <name> (<source URL>)
Searched: <query variants run, with each one's top candidates and their install counts>
Followed: <which steps ran, per skill>
Produced: <artifact paths, or "nothing on disk">
Skipped: <step and reason, or "none">
```

Name every skill, including the ones already on disk. For a skill read from the web, include the URL it came from. The `Searched:` line is the evidence step 3 ran, and it carries the candidates that lost as well as the ones that won: a run whose `Searched:` line is empty or holds no queries did not follow this skill. When one skill led the work and another only informed it, say so on the line. Then stop. No offer of further work.

## Ask-first list

Get a yes before heading into:

- package installs (`npm i`, `pip install`, `uv add`, `apt`, `cargo`, `go get`)
- cloning or downloading repositories, models, or datasets
- writes to config outside the working directory (`~/.pi`, `~/.agents`, `~/.claude`, shell rc files)
- anything needing credentials, logins, API keys, or paid API calls
- deleting or overwriting files the user already had

No asking needed for public web reads, new files inside the current project, or scripts the skill ships with.

## No match

Say the search came up empty, list the queries you tried, then finish the request with your own tools. Offer to keep the workflow as a reusable skill only when the user wants that.

## Choosing between candidates

Pick a set rather than always a single skill. Rank by fit to the job first: whether the candidate's steps and completion criteria produce the deliverable the request names. An installed skill earns no rank from being installed; installation only breaks ties, because it saves a fetch. Below fit, rank by install count, then source reputation. When a local candidate and an ecosystem candidate both fit, follow the better fit and name the other on the `Searched:` line. When the best match covers only part of a job, follow it for that part and finish the rest yourself. Drop any candidate that adds no step the others lack.

## Failure to avoid

Reaching for the local candidate and stopping. The local list holds what past sessions installed, not what the ecosystem has; a request whose best skill sits on the web runs worse when only the local list gets read. Step 3 runs on every request, and `Searched:` shows what it returned.
