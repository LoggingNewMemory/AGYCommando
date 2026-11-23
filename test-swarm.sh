#!/usr/bin/env bash

BASE_DIR="$(pwd)"
REPO_NAME="$(basename "$BASE_DIR")"
SWARM_ROOT="$(dirname "$BASE_DIR")/.${REPO_NAME}-swarm"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_SH="$SCRIPT_DIR/swarm.sh"

# Automatic conflict resolution modes:
# "union"  = Combine both versions without <<<<<<< markers (best default for merging multiple tasks)
# "theirs" = Favor incoming agent changes (overwrite conflicting lines)
# "force"  = Directly copy-overwrite entire files from agent to Main Tree (100% identical to agent worktree)
CONFLICT_MODE="theirs"

TASKS=()

if [ -f "$SWARM_SH" ]; then
    eval "$(sed -n '/^TASKS=(/,/^)/p' "$SWARM_SH")"
fi

if [ -d "$SWARM_ROOT" ]; then
    for dir in "$SWARM_ROOT"/*/; do
        [ -d "$dir" ] || continue
        task="$(basename "$dir")"
        found=false
        for t in "${TASKS[@]}"; do
            if [ "$t" = "$task" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            TASKS+=("$task")
        fi
    done
fi

if [ ${#TASKS[@]} -eq 0 ]; then
    echo "No swarm tasks found in $SWARM_ROOT!"
    exit 1
fi

prepare_worktree_diff() {
    local wt_dir="$1"
    git -C "$wt_dir" add -N . 2>/dev/null
    git -C "$wt_dir" reset -q HEAD -- node_modules 2>/dev/null || true
}

get_base_commit() {
    local wt_dir="$1"
    local wt_head main_head base
    wt_head="$(git -C "$wt_dir" rev-parse HEAD 2>/dev/null)" || { echo "HEAD"; return; }
    main_head="$(git -C "$BASE_DIR" rev-parse HEAD 2>/dev/null)" || { echo "HEAD"; return; }
    base="$(git -C "$BASE_DIR" merge-base "$main_head" "$wt_head" 2>/dev/null)"
    if [ -n "$base" ]; then
        echo "$base"
    else
        echo "HEAD"
    fi
}

apply_task() {
    local task="$1"
    local wt_dir="$SWARM_ROOT/$task"

    if [ ! -d "$wt_dir" ]; then
        echo "Worktree directory for [$task] not found!"
        return 1
    fi

    echo "Pulling changes from agent [$task] to Main Tree (Mode: $CONFLICT_MODE)..."
    prepare_worktree_diff "$wt_dir"

    local base_commit
    base_commit="$(get_base_commit "$wt_dir")"

    mapfile -t changed_files < <(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules')

    if [ ${#changed_files[@]} -eq 0 ]; then
        echo "Agent [$task] has not made any code changes (empty)."
        return 0
    fi

    for file in "${changed_files[@]}"; do
        local wt_file="$wt_dir/$file"
        local main_file="$BASE_DIR/$file"

        if [ ! -e "$wt_file" ]; then
            rm -f "$main_file"
            echo "  [-] Deleted: $file"
            continue
        fi

        mkdir -p "$(dirname "$main_file")"

        if [ ! -e "$main_file" ] || [ "$CONFLICT_MODE" = "force" ]; then
            cp -f "$wt_file" "$main_file"
            echo "  [F] Force copied: $file"
            continue
        fi

        local tmp_base
        tmp_base="$(mktemp)"
        if git -C "$wt_dir" show "$base_commit:$file" > "$tmp_base" 2>/dev/null; then
            if [ "$CONFLICT_MODE" = "theirs" ]; then
                git merge-file --theirs -q "$main_file" "$tmp_base" "$wt_file"
                echo "  [M] Merged (Auto-Theirs, 0 conflicts): $file"
            else
                git merge-file --union -q "$main_file" "$tmp_base" "$wt_file"
                echo "  [M] Merged (Auto-Union, 0 conflicts): $file"
            fi
        else
            cp -f "$wt_file" "$main_file"
            echo "  [+] New file: $file"
        fi
        rm -f "$tmp_base"
    done

    git reset -q HEAD 2>/dev/null || true

    echo "Successfully applied with 0 CONFLICT MARKERS! Ready for testing~"
}

unapply_task() {
    local task="$1"
    local wt_dir="$SWARM_ROOT/$task"

    echo "Reverting changes from [$task] in Main Tree..."
    prepare_worktree_diff "$wt_dir"

    local base_commit
    base_commit="$(get_base_commit "$wt_dir")"

    if git -C "$wt_dir" diff "$base_commit" -- . ':(exclude)node_modules' | git apply -R --3way --whitespace=nowarn - 2>/dev/null; then
        git reset -q HEAD 2>/dev/null || true
        echo "Changes from [$task] successfully removed from Main Tree!"
    else
        echo "Failed to revert patch with git apply -R, restoring touched files of [$task] to HEAD..."
        mapfile -t changed_files < <(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules')
        for file in "${changed_files[@]}"; do
            if git cat-file -e "HEAD:$file" 2>/dev/null; then
                git checkout HEAD -- "$file" 2>/dev/null
            else
                rm -f "$BASE_DIR/$file"
            fi
        done
        echo "Files related to [$task] have been reset to their initial state!"
    fi
}

show_summary() {
    echo ""
    echo "=== SWARM AGENTS WORK SUMMARY ==="
    for i in "${!TASKS[@]}"; do
        local t="${TASKS[$i]}"
        local wt_dir="$SWARM_ROOT/$t"
        if [ -d "$wt_dir" ]; then
            prepare_worktree_diff "$wt_dir"
            local base_commit
            base_commit="$(get_base_commit "$wt_dir")"
            local stat
            stat="$(git -C "$wt_dir" diff --shortstat "$base_commit" -- . ':(exclude)node_modules')"
            if [ -n "$stat" ]; then
                echo "  [$((i+1))] $t :$stat"
                git -C "$wt_dir" diff --name-status "$base_commit" -- . ':(exclude)node_modules' | sed 's/^/       /'
            else
                echo "  [$((i+1))] $t : (No changes)"
            fi
        else
            echo "  [$((i+1))] $t : (Worktree not found)"
        fi
    done
    echo "==========================================="
}

while true; do
    echo ""
    echo "=== ZERO-CONFLICT SWARM MENU ==="
    echo "  Current Mode: [$CONFLICT_MODE] (Type 'm' to switch mode)"
    echo "-------------------------------------------"
    for i in "${!TASKS[@]}"; do
        t="${TASKS[$i]}"
        wt_dir="$SWARM_ROOT/$t"
        status_badge="Empty"
        if [ -d "$wt_dir" ]; then
            prepare_worktree_diff "$wt_dir"
            base_commit="$(get_base_commit "$wt_dir")"
            changes_count=$(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' | sed '/^\s*$/d' | wc -l)
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
    read -rp "Choose an action (1-${#TASKS[@]}/a/m/u/s/r/q): " choice

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
            read -rp "Enter task number to revert (1-${#TASKS[@]}): " u_choice
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
            read -rp "Are you sure you want to reset all uncommitted changes in Main Tree? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                git reset --hard HEAD
                git clean -fd
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
