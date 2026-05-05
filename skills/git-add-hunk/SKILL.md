---
name: git-add-hunk
description: Stage specific hunks instead of whole files.
---

Stage only part of a modified file by saving the full diff and deleting unwanted hunks.

1. `git diff --no-color` — see all hunks; if empty, nothing to stage.
2. Save full diff to a temp file:
   ```
   PATCH=$(mktemp /tmp/git-add-hunk-XXXXXX.patch)
   git diff --no-color > "$PATCH"
   ```
3. Read `"$PATCH"` and **delete** unwanted `@@` blocks (each block is one hunk).
4. `git apply --cached "$PATCH"` — stage remaining hunks only.
5. If the apply fails: check `@@` line numbers match original diff output, or restart from step 1.
6. Verify: `git diff --cached` (staged) and `git diff` (remainder).
