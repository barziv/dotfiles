#!/usr/bin/env bash

# Fetch current tmux session name
CURRENT_NAME=$(tmux display-message -p '#S')
STATE=$1

# Strip out ALL existing suffixes to find the pure base name
BASE_NAME=${CURRENT_NAME%_working}
BASE_NAME=${BASE_NAME%_done}
BASE_NAME=${BASE_NAME%_waiting}

if [ "$STATE" == "working" ]; then
  tmux rename-session "${BASE_NAME}_working"
elif [ "$STATE" == "done" ]; then
  tmux rename-session "${BASE_NAME}_done"
elif [ "$STATE" == "waiting" ]; then
  tmux rename-session "${BASE_NAME}_waiting"
elif [ "$STATE" == "clear" ]; then
  # Only trigger a rename if a suffix actually exists
  if [[ "$CURRENT_NAME" != "$BASE_NAME" ]]; then
    tmux rename-session "$BASE_NAME"
  fi
fi
