#!/usr/bin/env bash

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
