#!/usr/bin/env bash

USER_SHELL="${SWARM_SHELL:-$(command -v fish 2>/dev/null || echo "${SHELL:-bash}")}"

launch_terminal() {
    local worktree_dir="$1"
    local task_name="$2"
    local branch_name="$3"
    local agent_cmd="${4:-$AGENT_CMD}"

    local cmd="echo '==> Task: $task_name ($branch_name)'; echo '==> Worktree: $worktree_dir'; $agent_cmd; exec $USER_SHELL"

    if command -v konsole &>/dev/null; then
        konsole --new-tab --workdir "$worktree_dir" -p tabtitle="Swarm: $task_name" -e "$USER_SHELL" -c "$cmd" &>/dev/null &
        sleep 0.2
        echo "  [+] Spawned Konsole tab: $task_name"
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal --tab --title="Swarm: $task_name" --working-directory="$worktree_dir" -- "$USER_SHELL" -c "$cmd" &>/dev/null &
        sleep 0.2
        echo "  [+] Spawned GNOME Terminal tab: $task_name"
    elif [ -n "$TERMINAL" ] && command -v "$TERMINAL" &>/dev/null; then
        "$TERMINAL" -e "$USER_SHELL -c 'cd \"$worktree_dir\" && $cmd'" &>/dev/null &
        echo "  [+] Spawned terminal ($TERMINAL): $task_name"
    else
        echo "  [!] Worktree ready at: $worktree_dir"
        echo "      To start agent: cd '$worktree_dir' && $agent_cmd"
    fi
}
