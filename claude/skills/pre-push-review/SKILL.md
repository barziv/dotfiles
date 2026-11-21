---
name: pre-push-review
description: Run the GitHub Claude review bot's review locally before pushing (the bot's own prompt, model and effort, in a fresh session), fix the findings, commit, stamp, push. Use when the user runs /pre-push-review, asks to push in a repo with the bot, or the push gate blocks a push.
---

# /pre-push-review — the PR bot's review, before the push

Goal: the GitHub `Claude Code Review` workflow finds nothing to comment on. It runs
`code-review high <PR>` and posts only **high** findings, so this runs the same review on the
user's own limits and fixes those first. Scripts: `~/.claude/scripts/push-review.sh`,
`~/.claude/scripts/bot-review.sh`.

Only start with a clean tree: commit or ask about uncommitted changes first. The review covers
committed work only.

## 1. Scope

`git fetch origin`, then `base=$(~/.claude/scripts/push-review.sh base)`. If
`git log $base..HEAD` is empty there is nothing to review: `push-review.sh stamp` and go to 5.
If `push-review.sh ok` already passes, go to 5: HEAD is the reviewed commit, or the commits after
it only change comments (`comments-only.mjs` compares the code with comments removed).

## 2. Review

From the repo, run `~/.claude/scripts/bot-review.sh <scratchpad>/bot-review.json` in the
background (it takes several minutes). It reads the bot's prompt, model, effort and tools from
`.github/workflows/claude-code-review.yml`, runs them in a fresh `claude -p` session on the local
branch, and prints the findings the bot would post, as JSON, already judged at the bot's bar.

Don't run the `code-review` skill in this session instead: it runs at this session's effort, and
your judging carries what this session already decided, so it misses findings the bot posts.
Only in a repo with no `claude-code-review.yml`, run the `code-review` skill with the arguments
`high <current branch name>`, and keep only the high findings: high only if it breaks behavior,
loses or corrupts data silently, or is a security issue.

## 3. Handle each finding

Every finding the script prints is one the bot would post. Check its failure scenario against the
code:

- Real: fix it, with a test when the repo has tests for that area.
- Cannot happen: drop it only when the code shows the scenario cannot happen, e.g. the value is
  set on the line before. Keep a one-line reason that names that line, for the report.
- Anything else — a known trade-off, out of scope, a product call, something dropped in an
  earlier round: ask the user in one line; don't push until they answer. Never drop one of these
  on your own: the bot has no memory, so it posts the finding again on every push.
- When the user accepts a trade-off, add a short code comment at that line saying what the
  trade-off is and why, so neither reviewer flags it again.

## 4. Commit and re-check

If you changed code: run the tests and lint for what you touched, then run step 2 again on the
new HEAD (max 3 rounds; still finding highs after 3 → stop and report to the user). When a round
comes back with no real high findings:

- `~/.claude/scripts/pipeline.sh stamp` (this review passed on the tree; no-op outside a ticket
  worktree), then commit: `fix: address pre-push review findings` (+ ticket id if any).
- `~/.claude/scripts/push-review.sh stamp`.

No code changes → `push-review.sh stamp` directly.

## 5. Push

If the user already asked to push, push now. Otherwise report and ask. Report in ≤5 lines:
findings fixed, findings dropped with reasons, rounds run.
