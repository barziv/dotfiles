---
name: ticket
description: Start work on a Linear ticket - fetch it, propose a branch, create a worktree + tmux session with nvim and a worker Claude. Use when the user runs /ticket INT-123 or asks to start a ticket.
argument-hint: <ticket-id e.g. INT-123>
disable-model-invocation: true
---

# /ticket — open a ticket worktree

You are the manager session, running in the repo's `main/` worktree (bare-clone layout:
`<root>/.git` is bare, worktrees are siblings like `<root>/main`, `<root>/<dir>`).

Ticket: `$ARGUMENTS`

## Steps

1. **Fetch the ticket** with the Linear MCP (`get_issue`). Read title, description, labels.

2. **Propose names.** Pick a type from the ticket: `feat`, `fix`, `chore`, `refactor`, `docs`.
   - Branch: `barz/<type>/<id-lowercase>-<slug>` — slug is 2–5 kebab-case words from the title.
     Example: `barz/feat/int-123-csv-export`.
   - Dir: `<slug>` (no id, no dots). Check `<root>/<dir>` and tmux session `<dir>` don't exist
     (`git worktree list`, `tmux has-session -t =<dir>`); if taken, append `-2`.

3. **Ask the user** with AskUserQuestion: show the ticket title in one line and offer the proposed
   branch + dir as the first (Recommended) option and one alternative. The user may type their own.
   Do nothing else until they answer.

4. **Run the setup script** with the accepted names:

   ```bash
   ~/.claude/scripts/wt-new.sh <branch> <dir> <TICKET-ID>
   ```

   It fetches origin/main, adds the worktree, copies config files, assigns ports, runs
   `pnpm install`, starts the pipeline, and opens tmux session `<dir>` (windows `nvim`, `claude`).
   It takes a minute or two. If it fails, show the error and stop — don't retry with other names
   without asking.

5. **Update Linear**: move the issue to the team's "In Progress" state and assign it to me
   (`update_issue` with `assignee: "me"`). If the state name differs, use the team's started state.

6. **Report** in 2–3 lines: branch, path, ports, and `prefix g` → `<dir>` to jump to the session.
