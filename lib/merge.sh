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


prepare_worktree_diff() {
    local wt_dir="$1"
    if is_worktree "$wt_dir"; then
        git -C "$wt_dir" add -N . 2>/dev/null || true
        git -C "$wt_dir" reset -q HEAD -- node_modules .venv venv "$TOOL_FOLDER_NAME" 2>/dev/null || true
    fi
}

get_base_commit() {
    local wt_dir="$1"
    if ! is_worktree "$wt_dir"; then
        return 1
    fi
    local wt_head main_head base
    wt_head="$(git -C "$wt_dir" rev-parse HEAD 2>/dev/null)" || return 1
    main_head="$(git -C "$BASE_DIR" rev-parse HEAD 2>/dev/null)" || { echo "$wt_head"; return 0; }
    base="$(git -C "$BASE_DIR" merge-base "$main_head" "$wt_head" 2>/dev/null)"
    if [ -n "$base" ]; then
        echo "$base"
    else
        echo "$main_head"
    fi
}

apply_task() {
    local task="$1"
    local wt_dir="$SWARM_ROOT/$task"

    if ! is_worktree "$wt_dir"; then
        echo "Valid worktree for [$task] not found at $wt_dir!"
        return 1
    fi

    echo "Pulling changes from agent [$task] into Main Tree (Mode: $CONFLICT_MODE)..."
    prepare_worktree_diff "$wt_dir"

    local base_commit
    base_commit="$(get_base_commit "$wt_dir")"
    if [ -z "$base_commit" ]; then
        echo "Could not determine base commit for [$task]."
        return 1
    fi

    mapfile -t changed_files < <(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" 2>/dev/null)

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

    if ! is_worktree "$wt_dir"; then
        echo "Valid worktree for [$task] not found at $wt_dir!"
        return 1
    fi

    echo "Reverting changes from [$task] in Main Tree..."
    prepare_worktree_diff "$wt_dir"

    local base_commit
    base_commit="$(get_base_commit "$wt_dir")"
    if [ -z "$base_commit" ]; then
        echo "Could not determine base commit for [$task]."
        return 1
    fi

    if git -C "$wt_dir" diff "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" 2>/dev/null | git -C "$BASE_DIR" apply -R --3way --whitespace=nowarn - 2>/dev/null; then
        git -C "$BASE_DIR" reset -q HEAD 2>/dev/null || true
        echo "Changes from [$task] successfully removed from Main Tree!"
    else
        echo "Failed to revert patch with git apply -R, restoring touched files of [$task] to HEAD..."
        mapfile -t changed_files < <(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" 2>/dev/null)
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
        if is_worktree "$wt_dir"; then
            prepare_worktree_diff "$wt_dir"
            local base_commit
            base_commit="$(get_base_commit "$wt_dir")"
            if [ -n "$base_commit" ]; then
                local stat
                stat="$(git -C "$wt_dir" diff --shortstat "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" 2>/dev/null)"
                if [ -n "$stat" ]; then
                    echo "  [$((i+1))] $t :$stat"
                    git -C "$wt_dir" diff --name-status "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" 2>/dev/null | sed 's/^/       /'
                else
                    echo "  [$((i+1))] $t : (No changes)"
                fi
            else
                echo "  [$((i+1))] $t : (Could not determine base commit)"
            fi
        elif [ -d "$wt_dir" ]; then
            echo "  [$((i+1))] $t : (Invalid worktree)"
        else
            echo "  [$((i+1))] $t : (Worktree not found)"
        fi
    done
    echo "==========================================="
}
