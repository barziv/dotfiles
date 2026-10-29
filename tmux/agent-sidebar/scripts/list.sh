#!/usr/bin/env bash
# Prints lines "<session>\t<display>", one per session, with an aggregated agent badge.
# The first 9 get a number: pressing it in the sidebar jumps there.

current=$(tmux display -p '#{session_name}')

# One line per pane that has an agent state: "session<TAB>state".
states=$(tmux list-panes -a -F '#{session_name}	#{@agent_state}' | awk -F'\t' '$2 != ""')

# Badge for a set of states: waiting beats done beats working.
badge() {
  case "$1" in
    *waiting*) printf '\033[31m?\033[0m' ;;
    *done*)    printf '\033[32m✓\033[0m' ;;
    *working*) printf '\033[33m●\033[0m' ;;
    *)         printf ' ' ;;
  esac
}

# Most recently accessed session first; the sidebar's own parking session is hidden.
i=0
tmux list-sessions -F '#{session_last_attached}	#{session_name}	#{session_windows}' | sort -rn | cut -f2- | grep -v '^_agent-sidebar	' | while IFS=$'\t' read -r s n; do
  i=$((i + 1))
  if [ "$i" -le 9 ]; then num="\033[34m$i\033[0m"; else num=' '; fi
  b=$(badge "$(awk -F'\t' -v s="$s" '$1 == s { print $2 }' <<<"$states")")
  if [ "$s" = "$current" ]; then
    printf '%s\t%b %s \033[1;35m%s\033[0m \033[90m%s\033[0m\n' "$s" "$num" "$b" "$s" "$n"
  else
    printf '%s\t%b %s %s \033[90m%s\033[0m\n' "$s" "$num" "$b" "$s" "$n"
  fi
done
