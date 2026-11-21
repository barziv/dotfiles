#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks git push in repos that run the GitHub Claude review bot until
# /pre-push-review passed on the exact HEAD (push-review.sh stamp). Other repos → no gate.

input=$(cat)
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

# Only git push, at a command boundary (also catches `git -C x push`). Deleting a branch is fine.
grep -Eq '(^|[;&|(]\s*)git(\s+-C\s+\S+)?\s+push\b' <<<"$cmd" || exit 0
grep -Eq '\s(--delete|-d)\b' <<<"$cmd" && exit 0

cd "$cwd" 2>/dev/null || exit 0
# Gate the repo the push runs in (`git -C x push`, `cd x && git push`), not the session's cwd,
# so pushing a non-Intera repo from an Intera session isn't blocked.
dir=$(grep -oE 'git\s+-C\s+\S+\s+push' <<<"$cmd" | head -1 | awk '{print $3}')
[ -n "$dir" ] || dir=$(grep -oE '(^|[;&|(]\s*)cd\s+[^;&|[:space:]]+' <<<"$cmd" | tail -1 | sed -E 's/.*cd[[:space:]]+//')
dir=${dir//[\"\']/}
dir=${dir/#\~/$HOME}
[ -n "$dir" ] && cd "$dir" 2>/dev/null
P=$(dirname "$0")/../push-review.sh
"$P" gated || exit 0
"$P" ok && exit 0

cat >&2 <<'EOF2'
Push gate: HEAD has not passed the local pre-push review, and changed more than comments since
the last one that did. Run /pre-push-review first — it runs
the same review as the GitHub Claude bot on your own limits and fixes what's relevant.
If the user explicitly said to push without it in this conversation, run
~/.claude/scripts/push-review.sh stamp and retry. Never stamp on your own judgement.
EOF2
exit 2
