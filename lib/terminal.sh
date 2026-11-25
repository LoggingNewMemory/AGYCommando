#!/usr/bin/env bash

# AGYCommando - A swarm orchestration and agent management utility designed exclusively for Antigravity CLI
# Copyright (C) 2026 Kana Wesley Yamada <albert.wesley.dion@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


USER_SHELL="${SWARM_SHELL:-$(command -v fish 2>/dev/null || echo "${SHELL:-bash}")}"

launch_terminal() {
    local worktree_dir="$1"
    local task_name="$2"
    local branch_name="$3"
    local agent_cmd="${4:-$AGENT_CMD}"

    local pid_dir="$SWARM_ROOT/.pids"
    local pid_file="$pid_dir/${task_name}.pid"
    mkdir -p "$pid_dir"

    local cmd="echo '==> Task: $task_name ($branch_name)'; echo '==> Worktree: $worktree_dir'; $agent_cmd; exec $USER_SHELL"

    if command -v konsole &>/dev/null; then
        konsole --new-tab --workdir "$worktree_dir" -p tabtitle="Swarm: $task_name" -e sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$pid_file" "$USER_SHELL" -c "$cmd" &>/dev/null &
        sleep 0.2
        echo "  [+] Spawned Konsole tab: $task_name"
    elif command -v gnome-terminal &>/dev/null; then
        gnome-terminal --tab --title="Swarm: $task_name" --working-directory="$worktree_dir" -- sh -c 'echo $$ > "$1"; shift; exec "$@"' _ "$pid_file" "$USER_SHELL" -c "$cmd" &>/dev/null &
        sleep 0.2
        echo "  [+] Spawned GNOME Terminal tab: $task_name"
    elif [ -n "$TERMINAL" ] && command -v "$TERMINAL" &>/dev/null; then
        "$TERMINAL" -e sh -c 'echo $$ > "$1"; cd "$2" && shift 2 && exec "$@"' _ "$pid_file" "$worktree_dir" "$USER_SHELL" -c "$cmd" &>/dev/null &
        echo "  [+] Spawned terminal ($TERMINAL): $task_name"
    else
        echo "  [!] Worktree ready at: $worktree_dir"
        echo "      To start agent: cd '$worktree_dir' && $agent_cmd"
    fi
}
