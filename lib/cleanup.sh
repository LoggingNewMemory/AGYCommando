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


clean_task() {
    local task="$1"
    local del_branch="${2:-true}"
    local wt_dir="$SWARM_ROOT/$task"
    local branch_name="swarm/$task"

    echo "Cleaning task: [$task] in $REPO_NAME..."

    if [ -L "$wt_dir/node_modules" ]; then
        rm -f "$wt_dir/node_modules"
    fi
    if [ -L "$wt_dir/.venv" ]; then
        rm -f "$wt_dir/.venv"
    fi
    if [ -L "$wt_dir/venv" ]; then
        rm -f "$wt_dir/venv"
    fi

    if [ -d "$wt_dir" ]; then
        echo "  [+] Removing worktree: $task..."
        git -C "$BASE_DIR" worktree remove --force "$wt_dir" 2>/dev/null || rm -rf "$wt_dir"
    else
        echo "  [*] Worktree directory $task does not exist."
    fi

    if [ "$del_branch" = true ]; then
        if git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/$branch_name"; then
            echo "  [+] Deleting branch: $branch_name"
            git -C "$BASE_DIR" branch -D "$branch_name"
        else
            echo "  [*] Branch $branch_name does not exist."
        fi
    fi

    if [ -f "$TASKS_FILE" ]; then
        sed -i "/^${task}$/d" "$TASKS_FILE"
    fi

    if [ -n "$SWARM_SH" ] && [ -f "$SWARM_SH" ]; then
        sed -i -E "/^[[:space:]]*[\"']?$(echo "$task" | sed 's/-/[- ]/g')[\"']?[[:space:]]*$/d" "$SWARM_SH" 2>/dev/null || true
    fi

    git -C "$BASE_DIR" worktree prune 2>/dev/null || true
    rmdir "$SWARM_ROOT" 2>/dev/null || true
    echo "Cleanup of [$task] completed!"
}

clean_all() {
    local del_branch="${1:-true}"

    echo "Starting cleanup of all Swarm tasks for: $REPO_NAME..."
    load_tasks
    for t in "${TASKS[@]}"; do
        clean_task "$t" "$del_branch"
    done
    git -C "$BASE_DIR" worktree prune 2>/dev/null || true
    rm -f "$TASKS_FILE" 2>/dev/null || true
    rmdir "$SWARM_ROOT" 2>/dev/null || true
    echo "All done! Workspace is clean and tidy!"
}
