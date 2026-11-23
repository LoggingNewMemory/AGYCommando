#!/usr/bin/env bash

detect_shell() {
    if [ -n "$SHELL" ] && command -v "$SHELL" &>/dev/null; then
        echo "$SHELL"
    elif command -v fish &>/dev/null; then
        echo "fish"
    elif command -v zsh &>/dev/null; then
        echo "zsh"
    elif command -v bash &>/dev/null; then
        echo "bash"
    else
        echo "sh"
    fi
}

USER_SHELL="$(detect_shell)"

launch_terminal() {
    local worktree_dir="$1"
    local task_name="$2"
    local branch_name="$3"
    local agent_cmd="${4:-$AGENT_CMD}"

    local startup_cmd="echo '========================================'; echo 'Swarm Task   : $task_name'; echo 'Agent Branch : $branch_name'; echo 'Worktree Dir : $worktree_dir'; echo '========================================'; $agent_cmd; exec $USER_SHELL"

    if [ -n "$TMUX" ]; then
        tmux new-window -c "$worktree_dir" -n "swarm:$task_name" "$USER_SHELL -c \"$startup_cmd\""
        echo "  [+] Spawned tmux window: swarm:$task_name"
    elif command -v konsole &>/dev/null; then
        konsole --new-tab --workdir "$worktree_dir" \
            -p tabtitle="Swarm: $task_name" \
            -e "$USER_SHELL" -c "$startup_cmd" &
        sleep 0.2
        echo "  [+] Spawned Konsole tab: $task_name"
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal --tab --title="Swarm: $task_name" --working-directory="$worktree_dir" -- "$USER_SHELL" -c "$startup_cmd" &
        sleep 0.2
        echo "  [+] Spawned GNOME Terminal tab: $task_name"
    elif command -v xfce4-terminal &>/dev/null; then
        xfce4-terminal --tab --title="Swarm: $task_name" --working-directory="$worktree_dir" -e "$USER_SHELL -c '$startup_cmd'" &
        sleep 0.2
        echo "  [+] Spawned XFCE Terminal tab: $task_name"
    elif command -v kitty &>/dev/null; then
        kitty --detach --directory="$worktree_dir" --title="Swarm: $task_name" "$USER_SHELL" -c "$startup_cmd" &
        echo "  [+] Spawned Kitty window: $task_name"
    elif command -v alacritty &>/dev/null; then
        alacritty --working-directory "$worktree_dir" --title "Swarm: $task_name" -e "$USER_SHELL" -c "$startup_cmd" &
        echo "  [+] Spawned Alacritty window: $task_name"
    elif command -v wezterm &>/dev/null; then
        wezterm start --cwd "$worktree_dir" "$USER_SHELL" -c "$startup_cmd" &
        echo "  [+] Spawned WezTerm window: $task_name"
    elif [ "$(uname)" = "Darwin" ]; then
        osascript -e "tell application \"Terminal\" to do script \"cd '$worktree_dir' && $startup_cmd\"" &
        echo "  [+] Spawned macOS Terminal window: $task_name"
    elif command -v xterm &>/dev/null; then
        xterm -title "Swarm: $task_name" -e "cd '$worktree_dir' && $startup_cmd" &
        echo "  [+] Spawned xterm window: $task_name"
    else
        echo "  [!] No supported terminal emulator detected."
        echo "      Worktree ready at: $worktree_dir"
        echo "      Run agent manually: cd '$worktree_dir' && $agent_cmd"
    fi
}
