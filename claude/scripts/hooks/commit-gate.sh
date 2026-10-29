#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks git commit/push in a ticket worktree until review passed on the
# exact current tree (pipeline.sh stamp). No pipeline in the worktree → no gate.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# Only git commit / git push, at a command boundary (also catches `git -C x commit`).
grep -Eq '(^|[;&|(]\s*)git(\s+-C\s+\S+)?\s+(commit|push)\b' <<<"$cmd" || exit 0

# Commands that cd elsewhere are checked from the cwd Claude reports.
cd "$cwd" 2>/dev/null || exit 0
P=$(dirname "$0")/../pipeline.sh
[ -f "$("$P" dir 2>/dev/null)/state.json" ] || exit 0

"$P" stamp-ok && exit 0

cat >&2 <<'EOF'
Commit gate: the working tree changed since the last passing review (or no review ran yet).
Run /cr first. If the user explicitly approved these exact changes in this conversation, run
~/.claude/scripts/pipeline.sh stamp and retry. Never stamp on your own judgement.
EOF
exit 2
