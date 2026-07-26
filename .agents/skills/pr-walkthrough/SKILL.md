---
name: pr-walkthrough
description: Walk through a pull request together, one section at a time. For each changed section show the code, the diff, and a TL;DR of what changed and why; then stop and let the user react, decide, and think out loud. Accumulate their decisions into an action list, and on approval implement the fixes. Use when the user says "walk me through this PR", "review the PR together", "pr walkthrough", or passes a PR number to walk.
---

# PR Walkthrough (together)

Go through a pull request **with** the user, section by section. You narrate each
change; they steer. You are not auto-reviewing — you are a guided reading where
the user's judgment drives every decision. Collect those decisions and, only when
they approve, make the fixes.

## 1. Resolve the target and load the diff

- **A number was passed** (`/pr-walkthrough 531`) → it's a GitHub PR:
  - `gh pr view <n> --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles` for context
  - `gh pr diff <n>` for the unified diff
- **Nothing passed** → the current branch is the PR: diff it against its base
  (`git diff main...HEAD`, or `@{upstream}...HEAD` if it tracks a remote). If that
  range is empty, fall back to `git diff HEAD`.
- **A branch name or path was passed** → diff that instead.

Read the PR title/body first so your TL;DRs reflect the author's stated intent,
not just the code.

## 2. Split into sections

One **section = one file** by default. Split a large file into its logical hunk
groups (a function, a block of related edits) and treat each as its own section
when the file is big or does several unrelated things. Merge trivially-coupled
files (a type + its one consumer) into a single section when it reads better.

Announce the plan up front: "N sections — I'll walk them one at a time." Then go
in an order that tells the story: entrypoint/domain first, then consumers, tests
last. Don't dump the list of all sections' contents — just the count and order.

## 3. Walk each section — ONE AT A TIME

For the current section, present exactly this, then **stop and wait**:

1. **Where** — `path/to/file.ts` (and the symbol/line range).
2. **The code** — show the actual diff hunk(s) for this section in a fenced block.
   Show enough surrounding context to make it readable; don't paste the whole file.
3. **TL;DR** — 1–3 sentences: *what* changed and *why* (infer the why from the
   code + PR intent; if you can't tell, say so and ask).
4. **Your read** — one short line of your own take **only if you have one**: a
   risk, a smell, a question, or "looks clean." Don't manufacture concerns.

Then hand it to the user. Do **not** advance to the next section on your own.

The user will react — approve it, ask you to change something, question why it's
there, push back, or think out loud. Your job each turn:

- **Answer their questions** about the section from the code (read more of the
  file / trace callers as needed — don't guess).
- **Capture any decision** into the action list (§4): what to change, and the
  user's stated reason. If they explain their thinking, record the *why* in their
  words — that reasoning is the point of doing this together.
- **Discuss, don't railroad.** If you disagree with a decision, say so once,
  briefly, then defer — it's their call.

Only move to the next section when the user signals they're done with this one
("next", "ok", "got it", or a new decision that closes it). If they go quiet with
just "next", that section is accepted as-is.

## 4. The action list

Maintain a running list across the whole walkthrough. Each entry:

> **`file:line`** — *what to change* — because *user's reason*

Keep it in memory as you go; don't re-print the whole list every section (it gets
noisy). If the user asks "what have we got so far?", print the current list.

## 5. Close out

When every section is walked, present the **consolidated action list** in full:
grouped by file, each with its change and the reason behind it. This is the
deliverable — the user should be able to read it and see every decision you two made.

Then ask for approval to implement. **Do not touch code before explicit approval.**

## 6. On approval — implement

Once approved:

- Make exactly the changes on the list — nothing extra, no scope creep, no
  "while I'm here." If implementing one surfaces a problem, stop and flag it.
- Group edits sensibly; keep the diff minimal.
- After the edits, run the relevant check (typecheck / the touched test / lint —
  whatever fits the repo) and report the result.
- Summarize what changed against the list so the user can tick it off.

If the user approves only *some* items ("do 1, 3, and 5"), do only those.

## Principles

- **They drive.** You surface and explain; the user decides. Never bulk-approve
  your own suggestions.
- **One section at a time.** The whole value is the guided pace — resist dumping
  the entire PR at once.
- **Reasons are the artifact.** Capture *why* each change is wanted, in the user's
  framing, not just *what*.
- **No edits until approval.** The walkthrough is read-only until §6.
