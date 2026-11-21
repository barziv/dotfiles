#!/usr/bin/env bash
# pipeline.sh — per-worktree ticket pipeline state, read by the commit gate and the pipeline mod.
#
# State lives in $(git rev-parse --git-dir)/claude-pipeline/ (per worktree, never committed):
#   state.json   {"ticket","stages":{plan,plan-review,plan-you,code,test,cr,you: pending|active|done|failed}}
#   cr-stamp     tree hash of the working tree the code review passed on
#
# Usage:
#   pipeline.sh init <ticket>            start a pipeline in this worktree
#   pipeline.sh set <stage> <status>     e.g. set plan-review done
#   pipeline.sh stamp                    record that review passed on the current tree
#   pipeline.sh stamp-ok                 exit 0 if the current tree matches the stamp
#   pipeline.sh show                     print state.json (exit 1 when no pipeline)
#   pipeline.sh dir                      print the state dir

set -euo pipefail

d="$(git rev-parse --absolute-git-dir)/claude-pipeline"
f="$d/state.json"

# Hash of the whole working tree (tracked + untracked, honoring .gitignore), without touching the index.
tree_hash() {
  local idx
  idx=$(mktemp)
  GIT_INDEX_FILE=$idx git read-tree HEAD
  GIT_INDEX_FILE=$idx git add -A
  GIT_INDEX_FILE=$idx git write-tree
  rm -f "$idx"
}

case "${1:-}" in
  init)
    mkdir -p "$d"
    jq -n --arg t "$2" '{ticket: $t, stages: {plan: "active", "plan-review": "pending", "plan-you": "pending", code: "pending", test: "pending", cr: "pending", you: "pending"}}' >"$f"
    rm -f "$d/cr-stamp"
    ;;
  set)
    [ -f "$f" ] || exit 0
    case "$2" in plan | plan-review | plan-you | code | test | cr | you) ;; *) echo "unknown stage $2" >&2; exit 1 ;; esac
    # Going back to a stage reopens it, so every stage after it has to run again.
    jq --arg s "$2" --arg v "$3" '
      ["plan", "plan-review", "plan-you", "code", "test", "cr", "you"] as $order
      | .stages[$s] = $v
      | if $v == "active" then
          reduce $order[($order | index($s)) + 1:][] as $later (.; .stages[$later] = "pending")
        else . end' "$f" >"$f.tmp" && mv "$f.tmp" "$f"
    ;;
  stamp)
    [ -d "$d" ] || exit 0
    tree_hash >"$d/cr-stamp"
    ;;
  stamp-ok)
    [ -f "$d/cr-stamp" ] && [ "$(cat "$d/cr-stamp")" = "$(tree_hash)" ]
    ;;
  show)
    cat "$f"
    ;;
  dir)
    echo "$d"
    ;;
  *)
    sed -n '2,15p' "$0" >&2
    exit 1
    ;;
esac
