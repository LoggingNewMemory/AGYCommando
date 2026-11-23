#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$LIB_DIR/.." && pwd)"

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

init_swarm_env() {
    resolve_target_repo

    if [ -z "$BASE_DIR" ] || [ ! -d "$BASE_DIR" ]; then
        echo "Error: Could not find target Git repository." >&2
        echo "Please run inside a Git repository or specify one with --repo <path>." >&2
        exit 1
    fi

    REPO_NAME="$(basename "$BASE_DIR")"
    SWARM_ROOT="$(dirname "$BASE_DIR")/.${REPO_NAME}-swarm"
    TASKS_FILE="$SWARM_ROOT/tasks.list"
    SWARM_SH="$SCRIPT_DIR/swarm.sh"

    REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    TOOL_FOLDER_NAME="$(basename "${REPO_ROOT:-$SCRIPT_DIR}")"
    if [[ "$SCRIPT_DIR" == "$BASE_DIR/"* ]] && [ -d "$BASE_DIR/.git/info" ]; then
        EXCLUDE_FILE="$BASE_DIR/.git/info/exclude"
        if ! grep -qFx "$TOOL_FOLDER_NAME/" "$EXCLUDE_FILE" 2>/dev/null; then
            echo "$TOOL_FOLDER_NAME/" >> "$EXCLUDE_FILE"
        fi
    fi
}

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
        local in_block=false
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^[[:space:]]*TASKS=\( ]]; then
                in_block=true
                continue
            fi
            if [ "$in_block" = true ]; then
                if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                    break
                fi
                local item
                item="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')"
                item="$(echo "$item" | tr ' ' '-' | tr -s '-')"
                if [ -n "$item" ] && [[ ! "$item" =~ ^# ]]; then
                    local found=false
                    for existing in "${TASKS[@]}"; do
                        if [ "$existing" = "$item" ]; then found=true; break; fi
                    done
                    if [ "$found" = false ]; then TASKS+=("$item"); fi
                fi
            fi
        done < "$SWARM_SH"
    fi
}
