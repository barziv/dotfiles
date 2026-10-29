#!/usr/bin/env bash
# Opens the sidebar (and focuses it), or closes it if it's open.
# Args: current pane id (unused), current window id.
# Closing parks the pane in a hidden session; opening brings it back with one join-pane,
# so the sidebar process is already running and the list already loaded.

source "$(dirname "$0")/common.sh"

win=$2
IFS=$'\t' read -r sb open width pid < <(tmux display -p '#{@agent_sidebar_pane}	#{@agent_sidebar_open}	#{@agent-sidebar-width}	#{@agent_sidebar_pid}')
width=${width:-32}

if [ "$open" = 1 ]; then
  close_sidebar "$sb"
  exit 0
fi

# Without -d, join-pane focuses the sidebar.
if [ -n "$sb" ] && tmux join-pane -hf -l "$width" -s "$sb" -t "$win" 2>/dev/null; then
  tmux set -g @agent_sidebar_open 1
  # Reload (the current session changed while parked) and put the cursor back on top.
  [ -n "$pid" ] && kill -USR2 "$pid" 2>/dev/null
  exit 0
fi

# First open (or the parked pane is gone): start the sidebar process.
tmux has-session -t "=$PARK" 2>/dev/null || tmux new-session -d -s "$PARK" sleep 2147483647
# Two args: tmux execs it directly instead of through the default shell.
sb=$(tmux split-window -hf -l "$width" -t "$win" -P -F '#{pane_id}' zsh "$SCRIPTS/sidebar.sh")
tmux set -g @agent_sidebar_pane "$sb" \; set -g @agent_sidebar_open 1
