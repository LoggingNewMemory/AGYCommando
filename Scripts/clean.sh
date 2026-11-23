#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_SH="$SCRIPT_DIR/swarm.sh"
TARGET_DIR=""
CLI_TASK=""
CLI_ALL=false

while [ $# -gt 0 ]; do
    case "$1" in
        --all|-a)
            CLI_ALL=true
            ;;
        -C|--repo)
            shift
            TARGET_DIR="$1"
            ;;
        --repo=*)
            TARGET_DIR="${1#*=}"
            ;;
        -h|--help)
            echo "Usage: clean.sh [OPTIONS] [TASK_NAME]"
            echo "Clean up swarm worktrees and branches for a project."
            echo ""
            echo "Options:"
            echo "  -a, --all               Clean all swarm tasks for the project"
            echo "  -C, --repo <PATH>       Target git repository path (default: auto-detected project)"
            echo "  -h, --help              Show this help message"
            exit 0
            ;;
        *)
            if [ -z "$TARGET_DIR" ] && [ -d "$1" ] && git -C "$1" rev-parse --show-toplevel &>/dev/null; then
                TARGET_DIR="$1"
            elif [ -z "$CLI_TASK" ]; then
                CLI_TASK="$1"
            fi
            ;;
    esac
    shift 2>/dev/null || break
done

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

load_tasks() {
    TASKS=()

    if [ -f "$TASKS_FILE" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue
            local found=false
            for t in "${TASKS[@]}"; do
                if [ "$t" = "$line" ]; then found=true; break; fi
            done
            if [ "$found" = false ]; then TASKS+=("$line"); fi
        done < "$TASKS_FILE"
    fi

    if [ -d "$SWARM_ROOT" ]; then
        for dir in "$SWARM_ROOT"/*/; do
            [ -d "$dir" ] || continue
            local task
            task="$(basename "$dir")"
            local found=false
            for t in "${TASKS[@]}"; do
                if [ "$t" = "$task" ]; then found=true; break; fi
            done
            if [ "$found" = false ]; then TASKS+=("$task"); fi
        done
    fi

    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        local task="${branch#refs/heads/swarm/}"
        local found=false
        for t in "${TASKS[@]}"; do
            if [ "$t" = "$task" ]; then found=true; break; fi
        done
        if [ "$found" = false ]; then TASKS+=("$task"); fi
    done < <(git -C "$BASE_DIR" for-each-ref --format='%(refname)' refs/heads/swarm/ 2>/dev/null)

    if [ -f "$SWARM_SH" ]; then
        local FILE_TASKS=()
        eval "$(sed -n '/^TASKS=(/,/)/p' "$SWARM_SH" 2>/dev/null | sed 's/TASKS=(/FILE_TASKS=(/' || true)"
        for t in "${FILE_TASKS[@]}"; do
            local found=false
            for existing in "${TASKS[@]}"; do
                if [ "$existing" = "$t" ]; then found=true; break; fi
            done
            if [ "$found" = false ]; then TASKS+=("$t"); fi
        done
    fi
}

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

    if [ -f "$BASE_DIR/swarm.sh" ]; then
        sed -i "/^[[:space:]]*[\"']$task[\"']/d" "$BASE_DIR/swarm.sh" 2>/dev/null || true
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

if [ "$CLI_ALL" = true ]; then
    clean_all true
    exit 0
fi

if [ -n "$CLI_TASK" ]; then
    clean_task "$CLI_TASK" true
    exit 0
fi

while true; do
    load_tasks

    if [ ${#TASKS[@]} -eq 0 ]; then
        echo ""
        echo "No swarm tasks found for: $REPO_NAME ($BASE_DIR)"
        break
    fi

    echo ""
    echo "=== SWARM CLEANUP MENU ($REPO_NAME) ==="
    for i in "${!TASKS[@]}"; do
        t="${TASKS[$i]}"
        wt_dir="$SWARM_ROOT/$t"
        branch_name="swarm/$t"

        wt_status="Missing"
        if [ -d "$wt_dir" ]; then
            wt_status="Exists"
        fi

        br_status="Missing"
        if git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/$branch_name"; then
            br_status="Exists"
        fi

        printf "  [%d] %-14s (Worktree: %-9s | Branch: %s)\n" "$((i+1))" "$t" "$wt_status" "$br_status"
    done

    echo "-------------------------------------------"
    echo "  [a] Clean ALL tasks at once"
    echo "  [q] Quit"
    echo "==========================================="
    read -rp "Select task to clean (1-${#TASKS[@]}/a/q): " choice || break

    case "$choice" in
        [1-9]*)
            idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#TASKS[@]}" ]; then
                target="${TASKS[$idx]}"
                clean_task "$target" true
            else
                echo "Invalid number!"
            fi
            ;;
        a|A)
            read -rp "Are you sure you want to clean ALL tasks? (y/N): " confirm_all || break
            if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                clean_all true
            fi
            ;;
        q|Q)
            echo "Exiting Swarm cleanup menu."
            break
            ;;
        *)
            echo "Unrecognized option!"
            ;;
    esac
done
