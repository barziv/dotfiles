#!/usr/bin/env bash
# agent-sidebar: toggleable session sidebar with Claude agent status badges.
#
# Options (set before this file runs):
#   @agent-sidebar-key         prefix key that opens/closes the sidebar (default: g; tmux.conf sets S)
#   @agent-sidebar-return-key  prefix key that leaves it open and returns to your pane (default: b)
#   @agent-sidebar-width       sidebar width in columns (default: 32)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$DIR/scripts"

key=$(tmux show -gqv @agent-sidebar-key)
key=${key:-g}

ret=$(tmux show -gqv @agent-sidebar-return-key)
ret=${ret:-b}

tmux bind-key "$key" run-shell "$S/toggle.sh '#{pane_id}' '#{window_id}'"
tmux bind-key "$ret" run-shell "$S/focus-main.sh"

# Keep the sidebar in whatever window the client is looking at.
# Indexed hooks so other plugins' hooks on the same events survive.
for hook in client-session-changed session-window-changed after-select-window after-new-window; do
  tmux set-hook -g "${hook}[90]" "run-shell -b '$S/follow.sh'"
done

# Redraw the list when sessions/windows change.
for hook in session-created session-closed session-renamed window-renamed window-unlinked; do
  tmux set-hook -g "${hook}[91]" "run-shell -b '$S/refresh.sh'"
done

# Looking at a pane clears its done/waiting badge.
tmux set-hook -g 'pane-focus-in[90]' "run-shell -b '$S/agent-state.sh clear #{pane_id}'"
