---
name: cr
description: Code review loop - spawn a fresh code-reviewer teammate on the current changes, answer its questions, fix findings, repeat until it passes. Use when the user runs /cr or /start-ticket reaches review.
---

# /cr — code review by a fresh teammate

Only start when your code change is finished and tests pass — never mid-edit or while waiting on
the user. `~/.claude/scripts/pipeline.sh set cr active`.

## Loop

1. Spawn a teammate using the **code-reviewer** agent type, named `code-reviewer`. Prompt:
   the ticket id, the plan path (`.claude/plans/<ID>.md`), and "review `git diff <base>`
   plus untracked files", where `<base>` is `~/.claude/scripts/push-review.sh base` (the stack
   parent on a stacked branch, else origin's default branch).
2. It may message you questions — answer from what you know (why you did something, what you
   tried). Escalate to the user only when you can't answer, then relay.
3. It ends with findings in the fixed format below. For each:
   - `blocker` / `major`: fix it, or reply to the reviewer with a concrete reason it's wrong.
   - `minor` / `nit`: fix if cheap, else keep it for the user's review.
4. Re-run tests. Send the reviewer "fixed: <ids>; disputed: <id — reason>" and ask it to re-check.
   It keeps its context, so it only re-reviews the delta.
5. Repeat until it replies `VERDICT: pass`. The reviewer stamps the tree itself
   (`pipeline.sh stamp`) — don't stamp on its behalf.

Then `pipeline.sh set cr done`, shut the teammate down.

Keep the findings you did **not** fix (kept minors, disputed items) — the user's Plannotator
review (/start-ticket step 7) starts with them.

## Finding format (what the reviewer returns)

```
F<n> · <file>:<line> · <blocker|major|minor|nit> · <issue> → <fix>
VERDICT: pass | changes
```
