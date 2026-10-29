#!/usr/bin/env bash
# Focuses the last-used non-sidebar pane in the sidebar's window.

source "$(dirname "$0")/common.sh"

sb=$(sidebar_pane)
[ -z "$sb" ] && exit 0

target=$(tmux list-panes -t "$sb" -F '#{pane_last} #{pane_active} #{pane_id}' |
  awk -v sb="$sb" '$3 != sb' | sort -r | head -1 | awk '{ print $3 }')
[ -n "$target" ] && tmux select-pane -t "$target"
