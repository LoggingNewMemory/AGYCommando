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


LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$LIB_DIR/.." && pwd)"

is_worktree() {
    local dir="$1"
    [ -n "$dir" ] && [ -d "$dir" ] && [ -e "$dir/.git" ] && git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null
}

normalize_task_name() {
    local t="$1"
    t="$(echo "$t" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')"
    local local_task="$(echo "$t" | tr ' ' '-' | tr -s '-')"
    if [ -n "$SWARM_ROOT" ] && [ -d "$SWARM_ROOT/$local_task" ] || { [ -n "$BASE_DIR" ] && git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/swarm/$local_task" 2>/dev/null; }; then
        echo "$local_task"
    else
        local clean="$(echo "$t" | tr ' /' '--' | tr -s '-')"
        clean="${clean#-}"
        clean="${clean%-}"
        echo "$clean"
    fi
}

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
    if [ ! -f "$SWARM_SH" ] && [ -f "$BASE_DIR/swarm.sh" ]; then
        SWARM_SH="$BASE_DIR/swarm.sh"
    fi

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
            local norm_line="$(normalize_task_name "$line")"
            [ -z "$norm_line" ] && continue
            local found=false
            for t in "${TASKS[@]}"; do
                if [ "$t" = "$norm_line" ]; then found=true; break; fi
            done
            if [ "$found" = false ]; then TASKS+=("$norm_line"); fi
        done < "$TASKS_FILE"
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree[[:space:]]+(.*)$ ]]; then
            local wt_path="${BASH_REMATCH[1]}"
            if [[ "$wt_path" == "$SWARM_ROOT/"* ]]; then
                local task="${wt_path#$SWARM_ROOT/}"
                local found=false
                for t in "${TASKS[@]}"; do
                    if [ "$t" = "$task" ]; then found=true; break; fi
                done
                if [ "$found" = false ]; then TASKS+=("$task"); fi
            fi
        fi
    done < <(git -C "$BASE_DIR" worktree list --porcelain 2>/dev/null)

    if [ -d "$SWARM_ROOT" ]; then
        while IFS= read -r git_entry; do
            [ -n "$git_entry" ] || continue
            local dir
            dir="$(dirname "$git_entry")"
            if is_worktree "$dir"; then
                local task="${dir#$SWARM_ROOT/}"
                local found=false
                for t in "${TASKS[@]}"; do
                    if [ "$t" = "$task" ]; then found=true; break; fi
                done
                if [ "$found" = false ]; then TASKS+=("$task"); fi
            fi
        done < <(find "$SWARM_ROOT" -mindepth 2 -name .git 2>/dev/null)
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

    local swarm_candidates=()
    [ -n "$SWARM_SH" ] && [ -f "$SWARM_SH" ] && swarm_candidates+=("$SWARM_SH")
    if [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/swarm.sh" ]; then
        if [ -z "$SWARM_SH" ] || [ ! "$BASE_DIR/swarm.sh" -ef "$SWARM_SH" ]; then
            swarm_candidates+=("$BASE_DIR/swarm.sh")
        fi
    fi

    for s_file in "${swarm_candidates[@]}"; do
        local in_block=false
        while IFS= read -r line || [ -n "$line" ]; do
            if [[ "$line" =~ ^[[:space:]]*TASKS=\((.*)\)[[:space:]]*$ ]]; then
                local -a inline_items=()
                eval "inline_items=(${BASH_REMATCH[1]})" 2>/dev/null || read -ra inline_items <<< "${BASH_REMATCH[1]}"
                for raw_item in "${inline_items[@]}"; do
                    local item="$(normalize_task_name "$raw_item")"
                    if [ -n "$item" ] && [[ ! "$item" =~ ^# ]]; then
                        local found=false
                        for existing in "${TASKS[@]}"; do
                            if [ "$existing" = "$item" ]; then found=true; break; fi
                        done
                        if [ "$found" = false ]; then TASKS+=("$item"); fi
                    fi
                done
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]*TASKS=\( ]]; then
                in_block=true
                continue
            fi
            if [ "$in_block" = true ]; then
                if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                    break
                fi
                local item_no_comment="${line%%#*}"
                local item
                item="$(echo "$item_no_comment" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')"
                item="$(normalize_task_name "$item")"
                if [ -n "$item" ] && [[ ! "$item" =~ ^# ]]; then
                    local found=false
                    for existing in "${TASKS[@]}"; do
                        if [ "$existing" = "$item" ]; then found=true; break; fi
                    done
                    if [ "$found" = false ]; then TASKS+=("$item"); fi
                fi
            fi
        done < "$s_file"
    done
}
