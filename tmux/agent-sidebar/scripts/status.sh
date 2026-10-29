#!/usr/bin/env bash
# Status-bar segment: counts of agents that need attention, e.g. "?1 ✓2".

states=$(tmux list-panes -a -F '#{@agent_state}')
waiting=$(grep -c '^waiting$' <<<"$states")
done=$(grep -c '^done$' <<<"$states")

out=""
[ "$waiting" -gt 0 ] && out+="#[fg=red]?${waiting} "
[ "$done" -gt 0 ] && out+="#[fg=green]✓${done} "
printf '%s' "$out"
