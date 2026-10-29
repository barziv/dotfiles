#!/bin/zsh
# The sidebar process: draws the session list and reads one key at a time.
#   j/k or arrows move · 1-9 jump to that session+close · enter switch+close
#   esc back to your pane · q close
# Signals: USR1 reloads the list, USR2 reloads and moves the cursor to the top.
# zsh, not macOS's bash 3.2: telling a lone ESC from an arrow or focus sequence
# needs a sub-second read timeout.

SCRIPTS=${0:A:h}

tmux select-pane -t "$TMUX_PANE" -T agent-sidebar
tmux set -g @agent_sidebar_pid $$

integer sel=1
names=()
rows=()

load() {
  names=()
  rows=()
  local name row
  while IFS=$'\t' read -r name row; do
    names+=("$name")
    rows+=("$row")
  done < <("$SCRIPTS/list.sh")
  (( sel > $#names )) && sel=$#names
  (( sel < 1 )) && sel=1
}

draw() {
  local i out=$'\e[H'
  for i in {1..$#rows}; do
    if (( i == sel )); then
      out+=$'\e[35m▌\e[0m\e[1m'"$rows[$i]"$'\e[0m\e[K\n'
    else
      out+=" $rows[$i]"$'\e[K\n'
    fi
  done
  print -rn -- "$out"$'\e[J'
}

goto() {
  [[ -n $names[$1] ]] || return
  "$SCRIPTS/goto.sh" "$names[$1]"
  sel=1
}

up() { (( sel > 1 )) && (( sel-- )); }
down() { (( sel < $#names )) && (( sel++ )); }

print -n $'\e[?25l\e[2J'
TRAPEXIT() { print -n $'\e[?25h'; }
TRAPUSR1() { load; draw; }
TRAPWINCH() { load; draw; }
TRAPUSR2() { sel=1; load; draw; }

load
draw
while :; do
  # The 5s timeout is the fallback refresh in case a hook was missed.
  if ! read -s -k 1 -t 5 key; then
    load
    draw
    continue
  fi
  case $key in
    j) down ;;
    k) up ;;
    [1-9]) goto $key ;;
    $'\n' | $'\r') goto $sel ;;
    q) "$SCRIPTS/toggle.sh" "$TMUX_PANE" '' ;;
    $'\e')
      # A sequence arrives whole (arrows ESC [ A/B, focus ESC [ I/O); a lone ESC
      # goes back to your pane.
      seq=
      while read -s -k 1 -t 0.02 c; do
        seq+=$c
        [[ $c == [A-Za-z~] ]] && break
      done
      case $seq in
        '[A' | 'OA') up ;;
        '[B' | 'OB') down ;;
        '') "$SCRIPTS/focus-main.sh" ;;
      esac
      ;;
  esac
  draw
done
