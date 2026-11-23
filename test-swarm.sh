#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_SH="$SCRIPT_DIR/swarm.sh"

# ==========================================
# Target Git Repository Resolution
# ==========================================
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

resolve_target_repo() {
    if [ -n "$TARGET_DIR" ]; then
        BASE_DIR="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
        if [ -n "$BASE_DIR" ]; then return 0; fi
    fi

    local current_git parent_git
    current_git="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    parent_git="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null || true)"

    # If this script folder is nested inside another git repo (e.g. cloned inside AnyaDisableThermal)
    if [ -n "$parent_git" ] && [ "$parent_git" != "$SCRIPT_DIR" ]; then
        if [ "$current_git" = "$parent_git" ] || [ "$current_git" = "$SCRIPT_DIR" ] || [ -z "$current_git" ]; then
            BASE_DIR="$parent_git"
            return 0
        fi
    fi

    if [ -n "$current_git" ]; then
        BASE_DIR="$current_git"
        return 0
    fi

    if [ -n "$parent_git" ]; then
        BASE_DIR="$parent_git"
        return 0
    fi

    BASE_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
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
TOOL_FOLDER_NAME="$(basename "$SCRIPT_DIR")"

# If SCRIPT_DIR is inside BASE_DIR, ensure it is ignored locally so git stays clean
if [[ "$SCRIPT_DIR" == "$BASE_DIR/"* ]] && [ -d "$BASE_DIR/.git/info" ]; then
    EXCLUDE_FILE="$BASE_DIR/.git/info/exclude"
    if ! grep -qFx "$TOOL_FOLDER_NAME/" "$EXCLUDE_FILE" 2>/dev/null; then
        echo "$TOOL_FOLDER_NAME/" >> "$EXCLUDE_FILE"
    fi
fi

# Automatic conflict resolution modes:
# "union"  = Combine both versions without <<<<<<< markers (best default for merging multiple tasks)
# "theirs" = Favor incoming agent changes (overwrite conflicting lines)
# "force"  = Directly copy-overwrite entire files from agent to Main Tree (100% identical to agent worktree)
CONFLICT_MODE="theirs"

load_tasks() {
    TASKS=()

    # 1. From project's tasks.list
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

    # 2. From worktree directories
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

    # 3. From git branches matching swarm/*
    while IFS= read -r branch; do
        [ -n "$branch" ] || continue
        local task="${branch#refs/heads/swarm/}"
        local found=false
        for t in "${TASKS[@]}"; do
            if [ "$t" = "$task" ]; then found=true; break; fi
        done
        if [ "$found" = false ]; then TASKS+=("$task"); fi
    done < <(git -C "$BASE_DIR" for-each-ref --format='%(refname)' refs/heads/swarm/ 2>/dev/null)

    # 4. Fallback to swarm.sh TASKS=(...) if defined
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

load_tasks

if [ ${#TASKS[@]} -eq 0 ]; then
    echo "No swarm tasks found for: $REPO_NAME ($BASE_DIR)"
    echo "Swarm root: $SWARM_ROOT"
    echo "To initialize agent tasks, run: ./swarm.sh <task1> <task2> ..."
    exit 1
fi

prepare_worktree_diff() {
    local wt_dir="$1"
    git -C "$wt_dir" add -N . 2>/dev/null || true
    git -C "$wt_dir" reset -q HEAD -- node_modules .venv venv "$TOOL_FOLDER_NAME" 2>/dev/null || true
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
        echo "Worktree directory for [$task] not found at $wt_dir!"
        return 1
    fi

    echo "Pulling changes from agent [$task] into Main Tree (Mode: $CONFLICT_MODE)..."
    prepare_worktree_diff "$wt_dir"

    local base_commit
    base_commit="$(get_base_commit "$wt_dir")"

    mapfile -t changed_files < <(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME")

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

    git -C "$BASE_DIR" reset -q HEAD 2>/dev/null || true

    echo "Successfully applied with 0 CONFLICT MARKERS! Ready for testing~"
}

unapply_task() {
    local task="$1"
    local wt_dir="$SWARM_ROOT/$task"

    echo "Reverting changes from [$task] in Main Tree..."
    prepare_worktree_diff "$wt_dir"

    local base_commit
    base_commit="$(get_base_commit "$wt_dir")"

    if git -C "$wt_dir" diff "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" | git -C "$BASE_DIR" apply -R --3way --whitespace=nowarn - 2>/dev/null; then
        git -C "$BASE_DIR" reset -q HEAD 2>/dev/null || true
        echo "Changes from [$task] successfully removed from Main Tree!"
    else
        echo "Failed to revert patch with git apply -R, restoring touched files of [$task] to HEAD..."
        mapfile -t changed_files < <(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME")
        for file in "${changed_files[@]}"; do
            if git -C "$BASE_DIR" cat-file -e "HEAD:$file" 2>/dev/null; then
                git -C "$BASE_DIR" checkout HEAD -- "$file" 2>/dev/null
            else
                rm -f "$BASE_DIR/$file"
            fi
        done
        echo "Files related to [$task] have been reset to their initial state!"
    fi
}

show_summary() {
    echo ""
    echo "=== SWARM AGENTS WORK SUMMARY ($REPO_NAME) ==="
    for i in "${!TASKS[@]}"; do
        local t="${TASKS[$i]}"
        local wt_dir="$SWARM_ROOT/$t"
        if [ -d "$wt_dir" ]; then
            prepare_worktree_diff "$wt_dir"
            local base_commit
            base_commit="$(get_base_commit "$wt_dir")"
            local stat
            stat="$(git -C "$wt_dir" diff --shortstat "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME")"
            if [ -n "$stat" ]; then
                echo "  [$((i+1))] $t :$stat"
                git -C "$wt_dir" diff --name-status "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" | sed 's/^/       /'
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
