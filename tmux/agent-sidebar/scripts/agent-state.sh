#!/usr/bin/env bash
# Records a Claude agent's state on its own tmux pane (@agent_state) and notifies.
# Called from Claude Code hooks: agent-state.sh working|done|waiting|end
# Called from tmux focus hook:   agent-state.sh clear <pane_id>

source "$(dirname "$0")/common.sh"

state=$1
pane=${2:-$TMUX_PANE}
[ -z "$pane" ] && exit 0

session=$(tmux display -p -t "$pane" '#{session_name}')
# 1 when the user is looking at this exact pane right now.
viewed=$(tmux display -p -t "$pane" '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}')
current=$(tmux display -p -t "$pane" '#{@agent_state}')

notify() {
  local done waiting
  done=$(tmux list-panes -a -F '#{@agent_state}' | grep -c '^done$')
  waiting=$(tmux list-panes -a -F '#{@agent_state}' | grep -c '^waiting$')
  terminal-notifier \
    -title "Claude Code" \
    -subtitle "$session" \
    -message "$1 · ${done} done, ${waiting} waiting" \
    -group "claude_${session}" \
    -sound Glass >/dev/null 2>&1
  # Auto-remove after 60 seconds
  (sleep 60 && terminal-notifier -remove "claude_${session}" >/dev/null 2>&1) &
  disown
}

case "$state" in
  working)
    tmux set -p -t "$pane" @agent_state working
    ;;
  done | waiting)
    if [ "$viewed" = 1 ]; then
      tmux set -pu -t "$pane" @agent_state
    else
      tmux set -p -t "$pane" @agent_state "$state"
      [ "$state" = done ] && notify "finished" || notify "needs you"
    fi
    ;;
  clear)
    case "$current" in done | waiting)
      tmux set -pu -t "$pane" @agent_state
      terminal-notifier -remove "claude_${session}" >/dev/null 2>&1
      ;;
    esac
    ;;
  end)
    tmux set -pu -t "$pane" @agent_state
    ;;
esac

tmux refresh-client -S 2>/dev/null
refresh_sidebar
