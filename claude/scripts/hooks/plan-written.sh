#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: when the ticket plan is written and plan review hasn't passed,
# remind the agent to get the plan reviewed before writing code.

input=$(cat)
path=$(jq -r '.tool_input.file_path // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")

case "$path" in */.claude/plans/*.md) ;; *) exit 0 ;; esac
cd "$cwd" 2>/dev/null || exit 0

P=$(dirname "$0")/../pipeline.sh
state=$("$P" show 2>/dev/null) || exit 0
[ "$(jq -r '.stages["plan-review"]' <<<"$state")" = done ] && exit 0

jq -n --arg p "$path" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext:
  ("Plan written to " + $p + ". Plan review has not passed yet: when the plan is complete, spawn the plan-reviewer teammate on it (see /start-ticket step 3) before writing any code.")}}'
