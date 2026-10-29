#!/usr/bin/env bash
# Moves the sidebar pane into the window the client is looking at.
# Arg (optional): target window id; defaults to the current client's window.

source "$(dirname "$0")/common.sh"

sb=$(sidebar_pane)
[ -z "$sb" ] && exit 0

win=${1:-$(tmux display -p '#{window_id}')}
[ "$(tmux display -p -t "$sb" '#{window_id}')" = "$win" ] && { refresh_sidebar; exit 0; }

# -d keeps focus on the window's own pane; -f makes the sidebar full height.
tmux join-pane -d -hbf -l "$(sidebar_width)" -s "$sb" -t "$win" 2>/dev/null
refresh_sidebar
