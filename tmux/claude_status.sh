#!/usr/bin/env bash

CURRENT_NAME=$(tmux display-message -p '#S')
WINDOW_NAME=$(tmux display-message -p '#W')
STATE=$1

# Strip out ALL existing suffixes to find the pure base name
BASE_NAME=${CURRENT_NAME%_working}
BASE_NAME=${BASE_NAME%_done}
BASE_NAME=${BASE_NAME%_waiting}

notify_waiting() {
  local session_name=$1
  local window_name=$2
  local count
  count=$(tmux list-sessions -F '#S' 2>/dev/null | grep -cE '_(waiting|done)$')

  # terminal-notifier -group lets -remove find this exact notification later
  terminal-notifier \
    -title "Claude Code" \
    -subtitle "${session_name} — ${window_name}" \
    -message "waiting — ${count} session(s)" \
    -group "claude_${session_name}" \
    -sound Glass 2>/dev/null

  # Auto-remove after 60 seconds (terminal-notifier -remove is non-blocking)
  (sleep 60 && terminal-notifier -remove "claude_${session_name}" 2>/dev/null) &
  disown

  printf '\a'
}

clear_notification() {
  local session_name=$1
  terminal-notifier -remove "claude_${session_name}" 2>/dev/null
}

if [ "$STATE" == "working" ]; then
  tmux rename-session "${BASE_NAME}_working"
elif [ "$STATE" == "done" ]; then
  tmux rename-session "${BASE_NAME}_done"
elif [ "$STATE" == "waiting" ]; then
  tmux rename-session "${BASE_NAME}_waiting"
  notify_waiting "$BASE_NAME" "$WINDOW_NAME"
elif [ "$STATE" == "clear" ]; then
  if [[ "$CURRENT_NAME" != "$BASE_NAME" ]]; then
    tmux rename-session "$BASE_NAME"
  fi
  clear_notification "$BASE_NAME"
fi
