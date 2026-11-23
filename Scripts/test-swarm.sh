#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        -C|--repo)
            shift
            TARGET_DIR="$1"
            ;;
        --repo=*)
            TARGET_DIR="${1#*=}"
            ;;
        -h|--help)
            echo "Usage: test-swarm.sh [OPTIONS]"
            echo "Interactive zero-conflict merge and testing harness for agent worktrees."
            exit 0
            ;;
        *)
            if [ -z "$TARGET_DIR" ] && [ -d "$1" ] && git -C "$1" rev-parse --show-toplevel &>/dev/null; then
                TARGET_DIR="$1"
            fi
            ;;
    esac
    shift 2>/dev/null || break
done

source "$SCRIPT_DIR/lib/core.sh"
init_swarm_env
source "$SCRIPT_DIR/lib/merge.sh"

CONFLICT_MODE="theirs"

load_tasks

if [ ${#TASKS[@]} -eq 0 ]; then
    echo "No swarm tasks found for: $REPO_NAME ($BASE_DIR)"
    echo "Swarm root: $SWARM_ROOT"
    echo "To initialize agent tasks, run: ./swarm.sh <task1> <task2> ..."
    exit 1
fi

while true; do
    load_tasks

    if [ ${#TASKS[@]} -eq 0 ]; then
        echo "No swarm tasks found for $REPO_NAME."
        break
    fi

    echo ""
    echo "=== ZERO-CONFLICT SWARM MENU ($REPO_NAME) ==="
    echo "  Current Mode: [$CONFLICT_MODE] (Type 'm' to switch mode)"
    echo "-------------------------------------------"
    for i in "${!TASKS[@]}"; do
        t="${TASKS[$i]}"
        wt_dir="$SWARM_ROOT/$t"
        status_badge="Empty"
        if [ -d "$wt_dir" ]; then
            prepare_worktree_diff "$wt_dir"
            base_commit="$(get_base_commit "$wt_dir")"
            changes_count=$(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" | sed '/^\s*$/d' | wc -l)
            if [ "$changes_count" -gt 0 ]; then
                status_badge="$changes_count files changed"
            fi
        else
            status_badge="Missing"
        fi
        printf "  [%d] Pull %-14s (%s)\n" "$((i+1))" "$t" "$status_badge"
    done
    echo "-------------------------------------------"
    echo "  [a] Pull ALL tasks into Main Tree"
    echo "  [m] Switch Merge Mode (union / theirs / force)"
    echo "  [u] Undo / Revert 1 task from Main Tree"
    echo "  [s] View file change details per agent"
    echo "  [r] Reset Main Tree (clean untracked and discard changes)"
    echo "  [q] Quit"
    echo "==========================================="
    read -rp "Choose an action (1-${#TASKS[@]}/a/m/u/s/r/q): " choice || break

    case "$choice" in
        [1-9]*)
            idx=$((choice - 1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#TASKS[@]}" ]; then
                apply_task "${TASKS[$idx]}"
            else
                echo "Invalid number!"
            fi
            ;;
        a|A)
            echo "Pulling all tasks sequentially..."
            for t in "${TASKS[@]}"; do
                apply_task "$t"
            done
            ;;
        m|M)
            if [ "$CONFLICT_MODE" = "union" ]; then
                CONFLICT_MODE="theirs"
            elif [ "$CONFLICT_MODE" = "theirs" ]; then
                CONFLICT_MODE="force"
            else
                CONFLICT_MODE="union"
            fi
            echo "Merge mode changed to: [$CONFLICT_MODE]!"
            ;;
        u|U)
            read -rp "Enter task number to revert (1-${#TASKS[@]}): " u_choice || break
            u_idx=$((u_choice - 1))
            if [ "$u_idx" -ge 0 ] && [ "$u_idx" -lt "${#TASKS[@]}" ]; then
                unapply_task "${TASKS[$u_idx]}"
            else
                echo "Invalid number!"
            fi
            ;;
        s|S)
            show_summary
            ;;
        r|R)
            read -rp "Are you sure you want to reset all uncommitted changes in Main Tree? (y/N): " confirm || break
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                git -C "$BASE_DIR" reset --hard HEAD
                git -C "$BASE_DIR" clean -fd -e "$TOOL_FOLDER_NAME"
                echo "Main Tree is clean again! (Original code in Swarm worktrees remains 100% safe!)"
            fi
            ;;
        q|Q)
            echo "Exiting Swarm Menu. Goodbye!"
            break
            ;;
        *)
            echo "Unrecognized option!"
            ;;
    esac
done
