---
name: start-ticket
description: Worker pipeline for a Linear ticket in its own worktree - grill the user, plan, plan review by a teammate, code, test, code review, user review. Use when started as `claude "/start-ticket INT-123"` or the user asks to work a ticket through the pipeline.
argument-hint: <ticket-id>
---

# /start-ticket — work a ticket through the pipeline

Ticket: `$ARGUMENTS`. You are the **coder** and team lead. Pipeline:

`plan › plan-review › plan-you › code › test › cr › you`

The two `you` stages are the user's reviews, in Plannotator (plan, then code).

Track each stage with `~/.claude/scripts/pipeline.sh set <stage> active|done|failed` — the
status band and the commit gate read it. If `pipeline.sh show` fails, run
`pipeline.sh init $ARGUMENTS` first.

**In T3 Code** (`$T3CODE_THREAD_ID` is set) the band isn't shown, so put the stage in this thread's
title instead. Every time you set a stage `active` or `failed` — here or inside a skill you run,
like /cr — rename the thread with `t3_thread_update` (`action: "rename"`, no `threadId`; load it
with ToolSearch) to `<dir> · <stage>`, where `<dir>` is `basename "$(git rev-parse --show-toplevel)"`
and `<stage>` is `plan`, `plan review`, `your plan review`, `code`, `test`, `CR` or `your review`.
Add ` failed` for a failed stage. When `you` is done, rename to `<dir> · done`. In a stack
(see the end) use `<dir> · <ID> · <stage>`, since one thread works many tickets.

## 1. Understand — grill-me

Fetch the ticket with the Linear MCP (`get_issue`, plus comments and linked issues). Read the
code it touches. Then run the **grill-me** skill with the user: interview them about the ticket
until you share one understanding of scope, behaviour and edge cases. Answer questions from the
codebase yourself instead of asking. Keep going until decisions are settled, not until a count.

## 2. Plan

Write `.claude/plans/$ARGUMENTS.md` (gitignored). Keep it short — one screen:

```md
# <ID> — <title>
Goal: <one sentence>
Decisions: <bullets from the grill-me session>
Changes: <file/module · what changes · why>, one line each
Tests: <the existing tests that cover it; new tests only if the user asked for them>
Out of scope: <bullets>
```

`pipeline.sh set plan done`.

## 3. Plan review — teammate

`pipeline.sh set plan-review active`. Spawn a teammate using the **plan-reviewer** agent type,
named `plan-reviewer`, with the prompt: the plan path, the ticket id, and the grill-me decisions.

- It messages you questions. Answer from the code and the grill-me decisions. Escalate a
  question to the user (AskUserQuestion) **only** when neither settles it, then relay the answer.
- Update the plan for every accepted change.
- On its `VERDICT: approve`, `pipeline.sh set plan-review done` and shut the teammate down.

## 3b. Your plan approval — Plannotator

`pipeline.sh set plan-you active`. Run (Bash, as-is):

```bash
plannotator annotate .claude/plans/$ARGUMENTS.md --gate
```

It opens the plan in the browser and returns at once. Say "Plan is in Plannotator" in one line and
end your turn — the user's decision arrives later as a message from Plannotator. Don't poll.

- Annotations / changes requested: revise the plan, then run the same command again.
- Approved (with or without notes): carry any notes into the work, `pipeline.sh set plan-you done`.
- Closed without a decision: ask the user in one line whether to reopen it. Closing is not approval.

## 4. Code

`pipeline.sh set code active`. Implement the plan. Don't commit yet (the gate blocks it until
review). If the plan turns out wrong, update the plan file and say so in one line.
`pipeline.sh set code done`.

## 5. Test

`pipeline.sh set test active`. Run the existing tests, lint and typecheck for the touched
packages. Fix until green. Don't write new tests unless the user explicitly asked for them in
this ticket; this pipeline is not that request. `pipeline.sh set test done`.

## 6. Code review — run /cr

Run the `/cr` skill. It spawns a fresh code-reviewer teammate, answers its questions, fixes the
findings, and loops until it passes.

## 7. Your code review — Plannotator

`pipeline.sh set you active`. If the reviewer left findings you didn't fix (kept minors, disputed
items), list them in ≤5 lines so the user can weigh them while reviewing. Then run (Bash, as-is):

```bash
plannotator review --gate
```

It opens the uncommitted diff in the browser and returns at once. Say "Code is in Plannotator"
in one line and end your turn — the user's review arrives later as a message from Plannotator.

- Feedback / annotations: address every one, re-run tests, then run the same command again.
- Approved (LGTM): `pipeline.sh stamp`, `pipeline.sh set you done`, then commit (conventional
  message with the ticket id) and ask before pushing or opening a PR. When the user says push,
  run /pre-push-review first (the push gate requires it where the GitHub review bot runs).
- Closed without a decision: ask the user in one line whether to reopen it. Closing is not approval.

## Stacked layers

When `.claude/plans/stack.md` exists, this worktree holds an epic as stacked PRs (opened by
`/ticket <ID> --stack`) and this ticket is one layer. Its parent is
`git config branch.<branch>.stackParent`, or `main` when unset. Differences:

- **Grill and plan**: read the earlier layers' plans in `.claude/plans/`; build on them, don't
  redo them.
- **Push**: the parent must already be on origin with its own PR. Then `git push -u origin HEAD`,
  `gh pr create --base <parent>`, `link_pull_request` (T3), and fill the PR and status
  (`in review`) in `stack.md`. Then say the next step in one line: `/ticket <next ID> --stack`
  (stack it on this layer), or with `--base <branch>` for another one.
- **Fixing a lower layer** (review feedback): `git switch` to it, fix, commit, then for each
  branch stacked above it, from the top of each chain: `git rebase --update-refs <fixed branch>`.
  Push the updated branches with `--force-with-lease` after asking.
- **Parent merged**: `git fetch origin +main:refs/remotes/origin/main`, rebase the child onto
  `origin/main` (the merged commits drop out), `git config --unset branch.<child>.stackParent`,
  `gh pr edit <child PR> --base main`, mark the parent `merged` in `stack.md`, and delete its
  local and remote branch after asking (the repo doesn't delete branches on merge).
