#!/usr/bin/env bash
# Shared helpers, sourced by the other scripts.

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Hidden session the sidebar pane is parked in while closed, so its process keeps running
# and opening is a single join-pane.
PARK=_agent-sidebar

sidebar_width() {
  local w
  w=$(tmux show -gqv @agent-sidebar-width)
  echo "${w:-32}"
}

# Prints the sidebar pane id while the sidebar is open, or nothing.
# Forgets a sidebar that was killed by hand.
sidebar_pane() {
  local sb open
  IFS=$'\t' read -r sb open < <(tmux display -p '#{@agent_sidebar_pane}	#{@agent_sidebar_open}')
  [ "$open" = 1 ] && [ -n "$sb" ] || return 0
  if tmux display -p -t "$sb" '#{pane_id}' >/dev/null 2>&1; then
    echo "$sb"
  else
    tmux set -gu @agent_sidebar_pane \; set -gu @agent_sidebar_open
  fi
}

# Parks the open sidebar pane in the hidden session; kills it if that fails.
close_sidebar() {
  tmux set -gu @agent_sidebar_open
  tmux break-pane -d -s "$1" -t "=$PARK:" 2>/dev/null && return
  tmux set -gu @agent_sidebar_pane
  tmux kill-pane -t "$1" 2>/dev/null
}

# Asks the sidebar process to reload its list (USR1), or to reload and reset (USR2).
refresh_sidebar() {
  local pid
  pid=$(tmux show -gqv @agent_sidebar_pid)
  [ -n "$pid" ] && kill "-${1:-USR1}" "$pid" 2>/dev/null
  return 0
}
