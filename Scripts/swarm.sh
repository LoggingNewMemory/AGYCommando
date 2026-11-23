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

resolve_target_repo() {
    if [ -n "$TARGET_DIR" ]; then
        BASE_DIR="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
        if [ -n "$BASE_DIR" ]; then return 0; fi
    fi

    local current_git repo_root parent_repo
    current_git="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    repo_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    parent_repo="$(git -C "$repo_root/.." rev-parse --show-toplevel 2>/dev/null || true)"

    if [ -n "$parent_repo" ] && [ "$parent_repo" != "$repo_root" ]; then
        if [ "$current_git" = "$parent_repo" ] || [ "$current_git" = "$repo_root" ] || [ -z "$current_git" ]; then
            BASE_DIR="$parent_repo"
            return 0
        fi
    fi

    if [ -n "$current_git" ]; then
        BASE_DIR="$current_git"
        return 0
    fi

    if [ -n "$parent_repo" ]; then
        BASE_DIR="$parent_repo"
        return 0
    fi

    BASE_DIR="$repo_root"
}

resolve_target_repo

if [ -z "$BASE_DIR" ] || [ ! -d "$BASE_DIR" ]; then
    echo "Error: Could not find target Git repository." >&2
    echo "Please run inside a Git repository or specify one with --repo <path>." >&2
    exit 1
fi

REPO_NAME="$(basename "$BASE_DIR")"
SWARM_ROOT="$(dirname "$BASE_DIR")/.${REPO_NAME}-swarm"
TASKS_FILE="$SWARM_ROOT/tasks.list"

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
TOOL_FOLDER_NAME="$(basename "${REPO_ROOT:-$SCRIPT_DIR}")"
if [[ "$SCRIPT_DIR" == "$BASE_DIR/"* ]] && [ -d "$BASE_DIR/.git/info" ]; then
    EXCLUDE_FILE="$BASE_DIR/.git/info/exclude"
    if ! grep -qFx "$TOOL_FOLDER_NAME/" "$EXCLUDE_FILE" 2>/dev/null; then
        echo "$TOOL_FOLDER_NAME/" >> "$EXCLUDE_FILE"
    fi
fi

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

AGENT_CMD="${CUSTOM_AGENT_CMD:-${SWARM_AGENT_CMD:-agy --dangerously-skip-permissions}}"

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

    local startup_cmd="echo '========================================'; echo 'Swarm Task   : $task_name'; echo 'Agent Branch : $branch_name'; echo 'Worktree Dir : $worktree_dir'; echo '========================================'; $AGENT_CMD; exec $USER_SHELL"

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
        echo "      Run agent manually: cd '$worktree_dir' && $AGENT_CMD"
    fi
}

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

    launch_terminal "$WORKTREE_DIR" "$task" "$BRANCH_NAME"
done

echo "----------------------------------------------------------"
echo "All agents dispatched! Happy experimenting~"
echo "To test/merge changes: run './test-swarm.sh' (or 'swarm.sh test')"
echo "To clean up: run './clean.sh' (or 'swarm.sh clean')"
