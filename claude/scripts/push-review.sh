#!/usr/bin/env bash
# push-review.sh — records that /pre-push-review passed on a commit, read by the push gate.
#
# State lives in $(git rev-parse --git-dir)/claude-push-review (per worktree, never committed):
# the HEAD sha the review passed on.
#
# Usage:
#   push-review.sh stamp     record that the review passed on HEAD
#   push-review.sh ok        exit 0 if HEAD matches the stamp, or only comments changed since it
#   push-review.sh base      print the ref to review against: the stack parent
#                            (git config branch.<branch>.stackParent), else origin's default branch
#   push-review.sh gated     exit 0 if this repo needs a review before push

set -euo pipefail

f="$(git rev-parse --absolute-git-dir)/claude-push-review"

case "${1:-}" in
  stamp)
    git rev-parse HEAD >"$f"
    ;;
  ok)
    [ -f "$f" ] || exit 1
    stamped=$(cat "$f")
    [ "$stamped" = "$(git rev-parse HEAD)" ] && exit 0
    # Commits after the reviewed one that only change comments need no new review.
    git merge-base --is-ancestor "$stamped" HEAD 2>/dev/null &&
      node "$(dirname "$0")/comments-only.mjs" "$stamped" HEAD
    ;;
  base)
    git config "branch.$(git branch --show-current).stackParent" ||
      git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main
    ;;
  gated)
    # Repos whose GitHub runs the Claude review bot.
    grep -Eq 'github\.com[:/]Intera-labs/momentum(\.git)?$' <<<"$(git remote get-url origin 2>/dev/null)"
    ;;
  *)
    sed -n '2,12p' "$0" >&2
    exit 1
    ;;
esac
