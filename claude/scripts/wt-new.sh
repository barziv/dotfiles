#!/usr/bin/env bash
# wt-new.sh — new ticket worktree + tmux session, for a bare-clone layout (<root>/.git + <root>/main).
#
# Usage: wt-new.sh <branch> <dir> <ticket-id>
#   run from inside any worktree of the repo (normally <root>/main).
#
# Does: fetch origin/main, worktree add <root>/<dir> -b <branch> origin/main, copy gitignored
# config (repo .worktreeinclude + ~/.claude/worktree-include), give it free ports, pnpm install,
# start the review pipeline, open tmux session <dir> with windows nvim + claude "/start-ticket <id>".

set -euo pipefail

branch=$1 dir=$2 ticket=$3
here=$(git rev-parse --show-toplevel)
root=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
main="$root/main"
[ -d "$main" ] || main=$here
wt="$root/$dir"
session=${dir//[.:]/-}

[ -e "$wt" ] && { echo "ERROR: $wt already exists" >&2; exit 1; }
tmux has-session -t "=$session" 2>/dev/null && { echo "ERROR: tmux session $session already exists" >&2; exit 1; }

echo "▸ Fetching origin/main…"
# No fetch refspec is configured on the bare clone, so name the ref explicitly.
git -C "$main" fetch --quiet origin +main:refs/remotes/origin/main
# Fast-forward the main worktree too when it's clean and on main; never fail on it.
if [ "$(git -C "$main" branch --show-current)" = main ] && [ -z "$(git -C "$main" status --porcelain -uno)" ]; then
  git -C "$main" merge --quiet --ff-only origin/main 2>/dev/null || echo "  (main not fast-forwarded)"
fi

echo "▸ Creating worktree ${wt} on ${branch}…"
git -C "$main" worktree add --quiet --no-track -b "$branch" "$wt" origin/main

echo "▸ Copying config files…"
{
  grep -v '^\s*\(#\|$\)' "$main/.worktreeinclude" 2>/dev/null || true
  grep -v '^\s*\(#\|$\)' "$HOME/.claude/worktree-include" 2>/dev/null || true
} | sort -u | while read -r f; do
  [ -f "$main/$f" ] || continue
  mkdir -p "$(dirname "$wt/$f")"
  cp "$main/$f" "$wt/$f"
  echo "  $f"
done

# Free ports so worktrees can run side by side (same keys as the team's worktree-setup.sh).
free_port() {
  local p
  for _ in $(seq 1 50); do
    p=$((RANDOM % 900 + 3100))
    [ "$p" != "${1:-}" ] && ! lsof -i :"$p" &>/dev/null && { echo "$p"; return; }
  done
  echo "ERROR: no free port" >&2; exit 1
}
api=$(free_port); ui=$(free_port "$api")
setkey() { [ -f "$1" ] && grep -q "^$2=" "$1" && sed -i '' "s|^$2=.*|$2=$3|" "$1" || true; }
setkey "$wt/momentum-api/.env" PORT "$api"
setkey "$wt/bruno/.env" API_PORT "$api"
setkey "$wt/momentum-ui/.env" VITE_API_URL "http://localhost:$api"
setkey "$wt/momentum-ui/.env" VITE_API_PORT "$api"
setkey "$wt/momentum-ui/.env" VITE_PORT "$ui"
echo "▸ Ports — API $api, UI $ui"

echo "▸ pnpm install…"
(cd "$wt" && pnpm install --reporter=silent) || echo "  pnpm install failed — run it in the session"

echo "▸ Starting pipeline…"
(cd "$wt" && "$(dirname "$0")/pipeline.sh" init "$ticket")

echo "▸ Opening tmux session ${session}…"
# Windows run the default shell; commands are typed in so quitting returns to the shell.
tmux new-session -d -s "$session" -c "$wt" -n nvim
tmux send-keys -t "=$session:nvim" nvim Enter
tmux new-window -d -t "=$session:" -c "$wt" -n claude
tmux send-keys -t "=$session:claude" "claude '/start-ticket $ticket'" Enter

echo "DONE session=$session path=$wt api=$api ui=$ui"
