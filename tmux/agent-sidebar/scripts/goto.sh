#!/usr/bin/env bash
# Switches the client to a session or session:window, then closes the sidebar.

source "$(dirname "$0")/common.sh"

tmux switch-client -t "=$1" 2>/dev/null || tmux switch-client -t "$1"
sb=$(sidebar_pane)
[ -z "$sb" ] && exit 0
tmux set -gu @agent_sidebar_pane
tmux kill-pane -t "$sb"
