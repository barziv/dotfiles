#!/usr/bin/env bash
# Shared helpers, sourced by the other scripts.

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOCK="${TMPDIR:-/tmp}/agent-sidebar-$(id -u).sock"

sidebar_width() {
  local w
  w=$(tmux show -gqv @agent-sidebar-width)
  echo "${w:-32}"
}

# Prints the sidebar pane id, or nothing. Forgets a sidebar that was killed by hand.
sidebar_pane() {
  local sb
  sb=$(tmux show -gqv @agent_sidebar_pane)
  [ -z "$sb" ] && return
  if tmux display -p -t "$sb" '#{pane_id}' >/dev/null 2>&1; then
    echo "$sb"
  else
    tmux set -gu @agent_sidebar_pane
  fi
}

refresh_sidebar() {
  [ -S "$SOCK" ] || return 0
  curl -s -m 1 --unix-socket "$SOCK" -XPOST http://localhost -d "reload-sync($SCRIPTS/list.sh)" >/dev/null 2>&1
}
