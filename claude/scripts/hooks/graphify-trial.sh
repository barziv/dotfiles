#!/bin/bash
# Temporary INT-870 trial: graphify hooks for every intera worktree before PR #129 merges.
# Skips checkouts whose project settings already wire graphify, so hooks never fire twice.
# Remove this script and its entries in ~/.claude/settings.json once the PR merges.

case "${CLAUDE_PROJECT_DIR-}" in */Code/intera/*) ;; *) exit 0 ;; esac
grep -q graphify "$CLAUDE_PROJECT_DIR/.claude/settings.json" 2>/dev/null && exit 0
command -v graphify >/dev/null 2>&1 || exit 0

if [ "$1" = start ]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 0
  nohup graphify update . >/dev/null 2>&1 </dev/null &
  exit 0
fi

graphify hook-guard "$1" || true
