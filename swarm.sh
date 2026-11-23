#!/usr/bin/env bash
set -e

TASKS=(
)

BASE_DIR="$(pwd)"
REPO_NAME="$(basename "$BASE_DIR")"
SWARM_ROOT="$(dirname "$BASE_DIR")/.${REPO_NAME}-swarm"

echo "Starting Agentic Swarm initialization for: $REPO_NAME"
mkdir -p "$SWARM_ROOT"

for task in "${TASKS[@]}"; do
    WORKTREE_DIR="$SWARM_ROOT/$task"
    BRANCH_NAME="swarm/$task"

    echo "----------------------------------------"
    echo "Setting up workspace clone for task: [$task]"

    if [ -d "$WORKTREE_DIR" ]; then
        echo "Worktree $WORKTREE_DIR already exists, skipping creation..."
    else
        if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
            git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
        else
            git worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR" HEAD
        fi
    fi

    if [ -d "$BASE_DIR/node_modules" ] && [ ! -e "$WORKTREE_DIR/node_modules" ]; then
        ln -s "$BASE_DIR/node_modules" "$WORKTREE_DIR/node_modules"
        echo "Successfully symlinked node_modules!"
    fi

    if command -v konsole &> /dev/null; then
        konsole --new-tab --workdir "$WORKTREE_DIR" \
            -p tabtitle="Swarm: $task" \
            -e fish -c "echo 'Agent Branch: $BRANCH_NAME'; agy --dangerously-skip-permissions; exec fish" &
        sleep 0.3
    else
        echo "Ready at: $WORKTREE_DIR (Please cd there and run agy)"
    fi
done

echo "----------------------------------------"
echo "All agents are dispatched to their respective workspaces! Happy experimenting~"
