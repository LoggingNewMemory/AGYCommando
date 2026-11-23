#!/usr/bin/env bash
set -e

TASKS=(
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""
CLI_TASKS=()
CUSTOM_AGENT_CMD=""

show_help() {
    cat << 'EOF'
Usage: swarm.sh [OPTIONS] [TASK_NAME ...]
       swarm.sh test [OPTIONS]
       swarm.sh clean [OPTIONS]

Spawns isolated Git worktrees and terminal tabs running autonomous AI agents (agy).

Options:
  -C, --repo <PATH>       Target git repository path (default: auto-detected project)
      --cmd <COMMAND>     Custom agent command (default: $SWARM_AGENT_CMD or 'agy --dangerously-skip-permissions')
  -h, --help              Show this help message

Subcommands:
  test                    Launch the interactive merge & testing harness (test-swarm.sh)
  clean                   Launch the cleanup utility (clean.sh)

Examples:
  ./swarm.sh auth ui api
  ./swarm.sh test
  ./swarm.sh clean --all
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        test)
            shift
            exec "$SCRIPT_DIR/test-swarm.sh" "$@"
            ;;
        clean)
            shift
            exec "$SCRIPT_DIR/clean.sh" "$@"
            ;;
        -C|--repo)
            shift
            TARGET_DIR="$1"
            ;;
        --repo=*)
            TARGET_DIR="${1#*=}"
            ;;
        --cmd)
            shift
            CUSTOM_AGENT_CMD="$1"
            ;;
        --cmd=*)
            CUSTOM_AGENT_CMD="${1#*=}"
            ;;
        -h|--help)
            show_help
            ;;
        *)
            CLI_TASKS+=("$1")
            ;;
    esac
    shift 2>/dev/null || break
done

if [ -z "$TARGET_DIR" ] && [ ${#CLI_TASKS[@]} -gt 0 ]; then
    if [ -d "${CLI_TASKS[0]}" ] && git -C "${CLI_TASKS[0]}" rev-parse --show-toplevel &>/dev/null; then
        TARGET_DIR="${CLI_TASKS[0]}"
        CLI_TASKS=("${CLI_TASKS[@]:1}")
    fi
fi

source "$SCRIPT_DIR/lib/core.sh"
init_swarm_env
source "$SCRIPT_DIR/lib/terminal.sh"

AGENT_CMD="${CUSTOM_AGENT_CMD:-${SWARM_AGENT_CMD:-agy --dangerously-skip-permissions}}"

if [ ${#CLI_TASKS[@]} -gt 0 ]; then
    TASKS=("${CLI_TASKS[@]}")
fi

if [ ${#TASKS[@]} -eq 0 ] && [ -f "$TASKS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue
        TASKS+=("$line")
    done < "$TASKS_FILE"
fi

if [ ${#TASKS[@]} -eq 0 ]; then
    echo "Target Project: $REPO_NAME ($BASE_DIR)"
    echo "No swarm tasks specified."
    read -rp "Enter task name(s) separated by spaces (e.g. auth ui backend): " input_tasks
    read -ra PROMPTED_TASKS <<< "$input_tasks"
    if [ ${#PROMPTED_TASKS[@]} -eq 0 ]; then
        echo "No tasks provided. Aborting."
        exit 1
    fi
    TASKS=("${PROMPTED_TASKS[@]}")
fi

mkdir -p "$SWARM_ROOT"
touch "$TASKS_FILE"

for task in "${TASKS[@]}"; do
    if ! grep -qFx "$task" "$TASKS_FILE" 2>/dev/null; then
        echo "$task" >> "$TASKS_FILE"
    fi
done

echo "=========================================================="
echo " Starting Agentic Swarm for: $REPO_NAME"
echo " Target Repository : $BASE_DIR"
echo " Swarm Root        : $SWARM_ROOT"
echo " Tasks             : ${TASKS[*]}"
echo "=========================================================="

for task in "${TASKS[@]}"; do
    WORKTREE_DIR="$SWARM_ROOT/$task"
    BRANCH_NAME="swarm/$task"

    echo "----------------------------------------------------------"
    echo "Setting up workspace for task: [$task]"

    if [ -d "$WORKTREE_DIR" ]; then
        echo "  [*] Worktree directory already exists, reusing: $WORKTREE_DIR"
    else
        if git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
            git -C "$BASE_DIR" worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
        else
            git -C "$BASE_DIR" worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR" HEAD
        fi
        echo "  [+] Created worktree on branch '$BRANCH_NAME'"
    fi

    if [ -d "$BASE_DIR/node_modules" ] && [ ! -e "$WORKTREE_DIR/node_modules" ]; then
        ln -s "$BASE_DIR/node_modules" "$WORKTREE_DIR/node_modules"
        echo "  [+] Symlinked node_modules"
    fi
    if [ -d "$BASE_DIR/.venv" ] && [ ! -e "$WORKTREE_DIR/.venv" ]; then
        ln -s "$BASE_DIR/.venv" "$WORKTREE_DIR/.venv"
        echo "  [+] Symlinked .venv"
    elif [ -d "$BASE_DIR/venv" ] && [ ! -e "$WORKTREE_DIR/venv" ]; then
        ln -s "$BASE_DIR/venv" "$WORKTREE_DIR/venv"
        echo "  [+] Symlinked venv"
    fi

    launch_terminal "$WORKTREE_DIR" "$task" "$BRANCH_NAME" "$AGENT_CMD"
done

echo "----------------------------------------------------------"
echo "All agents dispatched! Happy experimenting~"
echo "To test/merge changes: run './test-swarm.sh' (or 'swarm.sh test')"
echo "To clean up: run './clean.sh' (or 'swarm.sh clean')"
