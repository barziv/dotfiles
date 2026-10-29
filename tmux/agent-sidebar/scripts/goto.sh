#!/usr/bin/env bash
# Closes the sidebar, then switches the client to a session or session:window.
# Closing first so follow.sh (on client-session-changed) doesn't carry it along.

source "$(dirname "$0")/common.sh"

sb=$(sidebar_pane)
[ -n "$sb" ] && close_sidebar "$sb"
tmux switch-client -t "=$1" 2>/dev/null || tmux switch-client -t "$1"
