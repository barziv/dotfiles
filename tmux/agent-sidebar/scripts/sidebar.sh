#!/usr/bin/env bash
# The sidebar process: a persistent fzf list, reloaded over a unix socket.
#   j/k move · 1-9 jump to that session+close · enter switch+close · / search (esc ends search) · esc back to your pane · q close

source "$(dirname "$0")/common.sh"

tmux select-pane -T agent-sidebar
rm -f "$SOCK"

# Fallback refresh in case a hook was missed.
(while sleep 5; do refresh_sidebar; done) &
poller=$!
trap 'kill $poller 2>/dev/null; rm -f "$SOCK"' EXIT

digits='1,2,3,4,5,6,7,8,9'
nav="rebind(j,k,q,/,$digits)"
esc_cmd='if [ "$FZF_INPUT_STATE" = hidden ]; then echo "execute-silent('"$SCRIPTS"'/focus-main.sh)"; else echo "hide-input+'"$nav"'"; fi'

# 1-9: jump to the Nth session, if there is one (digits type normally while searching).
jump=()
for n in 1 2 3 4 5 6 7 8 9; do
  # \${o}1} spells {1} so fzf expands it after pos(), not before the transform runs.
  jump+=(--bind "$n:transform:o={; [ \$FZF_MATCH_COUNT -ge $n ] && echo \"pos($n)+execute-silent($SCRIPTS/goto.sh \${o}1})\"")
done

while [ "$(tmux show -gqv @agent_sidebar_pane)" = "$TMUX_PANE" ]; do
  : | fzf \
    --listen "$SOCK" \
    --with-shell 'bash -c' \
    --ansi --no-sort --layout reverse --no-input \
    --delimiter '\t' --with-nth 2 --track --id-nth 1 \
    --info hidden --pointer '▌' --gutter ' ' --no-scrollbar \
    --border none --header-border bottom \
    --color 'pointer:magenta,current-bg:-1,current-fg:-1:bold' \
    --bind "start:reload-sync($SCRIPTS/list.sh)" \
    --bind 'j:down,k:up' \
    "${jump[@]}" \
    --bind "/:show-input+unbind(j,k,q,/,$digits)" \
    --bind "esc:clear-query+transform:$esc_cmd" \
    --bind 'ctrl-c:ignore,ctrl-g:ignore,ctrl-q:ignore' \
    --bind "q:execute-silent($SCRIPTS/toggle.sh $TMUX_PANE '')" \
    --bind "enter:execute-silent($SCRIPTS/goto.sh {1})+clear-query+hide-input+$nav"
done
