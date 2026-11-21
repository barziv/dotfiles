---
name: ticket
description: Start work on a Linear ticket - fetch it, propose a branch, create a worktree and open a worker Claude on it (tmux session with nvim, or a T3 Code thread when run inside T3 Code). Use when the user runs /ticket INT-123 or asks to start a ticket.
argument-hint: <ticket-id e.g. INT-123> [--stack [--base <branch>]]
disable-model-invocation: true
---

# /ticket — open a ticket worktree

You are the manager session, running in the repo's `main/` worktree (bare-clone layout:
`<root>/.git` is bare, worktrees are siblings like `<root>/main`, `<root>/<dir>`).

Ticket: `$ARGUMENTS`

**Mode:** if `$T3CODE_THREAD_ID` is set (check with `echo $T3CODE_THREAD_ID`), you run inside
T3 Code — use **T3 mode**: open the worker as a T3 Code thread instead of a tmux session.
Otherwise use **tmux mode**.

**Stack mode** (`--stack`): stacked PRs for an epic, one branch and one PR per ticket, all in one
worktree and one worker thread. A branch's parent is in `git config branch.<branch>.stackParent`
(no value = `main`); `.claude/plans/stack.md` (gitignored) is the overview. Two cases:

- **First layer** — the current worktree has no `.claude/plans/stack.md` (normally you are in
  `main/`): run the steps below, with these changes. Dir is the epic's slug, not the ticket's
  (`<epic-slug>`, e.g. `onprem-terraform`, from the Linear project name), and the thread title is
  that slug too. `--base` is not supported here: the first layer branches from `main`. After step
  4, write `<root>/<dir>/.claude/plans/stack.md`:

  ```md
  # Stack — <Linear project name>
  | Ticket | Branch | Parent | PR | Status |
  |---|---|---|---|---|
  | <ID> | <branch> | main | | in progress |
  ```

- **Next layer** — the current worktree has `.claude/plans/stack.md` (you are the epic's worker
  thread). Don't run steps 4–5; no new worktree, project or thread:
  1. The tree must be clean (the current layer committed). If not, stop and say so.
  2. Parent: `--base <branch>`, else the current branch. A parent of `main` means `origin/main`
     after `git fetch origin +main:refs/remotes/origin/main`.
  3. Ask for the branch name as in step 3 (no dir), then `git switch -c <branch> <parent>`,
     `git config branch.<branch>.stackParent <parent>` (skip it for `main`), and
     `~/.claude/scripts/pipeline.sh init <ID>`.
  4. Add the row to `stack.md`, do step 6, then run the **start-ticket** skill with `<ID>` in
     this thread.

## Steps

1. **Fetch the ticket** with the Linear MCP (`get_issue`). Read title, description, labels.

2. **Propose names.** Pick a type from the ticket: `feat`, `fix`, `chore`, `refactor`, `docs`.
   - Branch: `barz/<type>/<id-lowercase>-<slug>` — slug is 2–5 kebab-case words from the title.
     Example: `barz/feat/int-123-csv-export`.
   - Dir: `<number>-<slug>` (the ticket number without the `INT-` prefix, no dots), e.g.
     `123-csv-export`, so worktrees sort and read by ticket. Check `<root>/<dir>` doesn't exist (`git worktree list`) and,
     in tmux mode only, that tmux session `<dir>` doesn't exist (`tmux has-session -t =<dir>`);
     if taken, append `-2`.

3. **Ask the user** with AskUserQuestion: show the ticket title in one line and offer the proposed
   branch + dir as the first (Recommended) option and one alternative. The user may type their own.
   Do nothing else until they answer.

4. **Run the setup script** with the accepted names. In T3 mode, add `--no-tmux`:

   ```bash
   ~/.claude/scripts/wt-new.sh <branch> <dir> <TICKET-ID>            # tmux mode
   ~/.claude/scripts/wt-new.sh <branch> <dir> <TICKET-ID> --no-tmux  # T3 mode
   ```

   It fetches origin/main, adds the worktree, copies config files, assigns ports, runs
   `pnpm install`, and starts the pipeline. In tmux mode it also opens tmux session `<dir>`
   (windows `nvim`, `claude`). It takes a minute or two. If it fails, show the error and stop —
   don't retry with other names without asking.

5. **T3 mode only — open the worker thread** (load the T3 tools with ToolSearch first):
   1. `t3_project_create` with `title: "<dir>"`, `workspaceRoot: "<root>/<dir>"`. Each worktree
      is its own T3 project, like the existing ones.
   2. `t3_thread_launch` with that `projectId`, `title: "<slug>"` (the branch slug, e.g.
      `csv-export`: no ticket id, no prefix, so the sidebar says what the thread is for; the
      project title already carries the id),
      `message: "/start-ticket <TICKET-ID>"`,
      `workspaceStrategy: {type: "existing_worktree", worktreePath: "<root>/<dir>"}`. Leave model
      and modes unset so they inherit yours. Not `type: "root"`: T3 only restores files on rewind
      for threads bound to a worktree.
   3. Focus it in the app: get the `environmentId` from `t3_environment_read`, then run
      `open "<scheme>://threads/<environmentId>/<threadId>"`. `<scheme>` is the app this session
      runs in: `barvaz-code` when `$T3CODE_CLI_PATH` is under `~/.barvaz_code/` (the Barvaz Code
      fork), else `t3code`. A `t3code://` link always opens the official T3 Code app.

6. **Update Linear**: move the issue to the team's "In Progress" state and assign it to me
   (`update_issue` with `assignee: "me"`). If the state name differs, use the team's started state.

7. **Report** in 2–3 lines: branch, path, ports, and then either `prefix g` → `<dir>` to jump to
   the session (tmux mode) or the new thread's `link` (T3 mode).
