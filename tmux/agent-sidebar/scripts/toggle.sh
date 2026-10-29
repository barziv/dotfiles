#!/usr/bin/env bash
# Opens the sidebar (and focuses it), or closes it if it's open.
# Args: current pane id (unused), current window id.

source "$(dirname "$0")/common.sh"

win=$2
sb=$(sidebar_pane)

if [ -z "$sb" ]; then
  sb=$(tmux split-window -hbf -l "$(sidebar_width)" -t "$win" -P -F '#{pane_id}' "$SCRIPTS/sidebar.sh")
  tmux set -g @agent_sidebar_pane "$sb"
else
  tmux set -gu @agent_sidebar_pane
  tmux kill-pane -t "$sb"
fi
