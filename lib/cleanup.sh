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


remove_task_from_swarm_file() {
    local swarm_file="$1"
    local target_task="$2"
    local norm_target
    norm_target="$(normalize_task_name "$target_task")"

    [ -f "$swarm_file" ] || return 0

    local tmp_swarm
    tmp_swarm="$(mktemp)"
    local in_tasks_block=false

    while IFS= read -r line || [ -n "$line" ]; do
        # Check for single-line TASKS=( ... )
        if [[ "$line" =~ ^([[:space:]]*TASKS=\()(.*)(\)[[:space:]]*)$ ]]; then
            local prefix="${BASH_REMATCH[1]}"
            local body="${BASH_REMATCH[2]}"
            local suffix="${BASH_REMATCH[3]}"
            local new_body=""
            local -a items=()
            eval "items=($body)" 2>/dev/null || read -ra items <<< "$body"
            for item in "${items[@]}"; do
                local norm_item
                norm_item="$(normalize_task_name "$item")"
                if [ "$item" = "$target_task" ] || [ "$norm_item" = "$norm_target" ] || [ "$norm_item" = "$target_task" ]; then
                    continue
                fi
                if [[ "$item" =~ [[:space:]] ]]; then
                    new_body+="${new_body:+ }\"$item\""
                else
                    new_body+="${new_body:+ }$item"
                fi
            done
            if [ -n "$new_body" ]; then
                echo "${prefix} ${new_body} ${suffix}" >> "$tmp_swarm"
            else
                echo "${prefix}${suffix}" >> "$tmp_swarm"
            fi
            continue
        fi

        # Check for start of multi-line TASKS=(
        if [[ "$line" =~ ^[[:space:]]*TASKS=\( ]]; then
            in_tasks_block=true
            echo "$line" >> "$tmp_swarm"
            continue
        fi

        if [ "$in_tasks_block" = true ]; then
            if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                in_tasks_block=false
                echo "$line" >> "$tmp_swarm"
                continue
            fi

            local raw_item="$line"
            local item_no_comment="${raw_item%%#*}"
            local item
            item="$(echo "$item_no_comment" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')"

            if [ -n "$item" ]; then
                local norm_item
                norm_item="$(normalize_task_name "$item")"
                if [ "$item" = "$target_task" ] || [ "$norm_item" = "$norm_target" ] || [ "$norm_item" = "$target_task" ]; then
                    continue
                fi
            fi
        fi

        echo "$line" >> "$tmp_swarm"
    done < "$swarm_file"

    chmod --reference="$swarm_file" "$tmp_swarm" 2>/dev/null || true
    mv -f "$tmp_swarm" "$swarm_file"
}

empty_tasks_in_swarm_file() {
    local swarm_file="$1"
    [ -f "$swarm_file" ] || return 0

    local tmp_swarm
    tmp_swarm="$(mktemp)"
    local in_tasks_block=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^([[:space:]]*TASKS=\()(.*)(\)[[:space:]]*)$ ]]; then
            local prefix="${BASH_REMATCH[1]}"
            local suffix="${BASH_REMATCH[3]}"
            echo "${prefix}${suffix}" >> "$tmp_swarm"
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*TASKS=\( ]]; then
            in_tasks_block=true
            echo "$line" >> "$tmp_swarm"
            continue
        fi

        if [ "$in_tasks_block" = true ]; then
            if [[ "$line" =~ ^[[:space:]]*\) ]]; then
                in_tasks_block=false
                echo "$line" >> "$tmp_swarm"
                continue
            fi
            continue
        fi

        echo "$line" >> "$tmp_swarm"
    done < "$swarm_file"

    chmod --reference="$swarm_file" "$tmp_swarm" 2>/dev/null || true
    mv -f "$tmp_swarm" "$swarm_file"
}

clean_task() {
    local task_input="$1"
    local del_branch="${2:-true}"
    local task
    task="$(normalize_task_name "$task_input")"

    local wt_dir="$SWARM_ROOT/$task"
    if [ ! -d "$wt_dir" ] && [ -d "$SWARM_ROOT/$task_input" ]; then
        wt_dir="$SWARM_ROOT/$task_input"
    fi

    local branch_name="swarm/$task"
    if ! git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
        if git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/swarm/$task_input" 2>/dev/null; then
            branch_name="swarm/$task_input"
        fi
    fi

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

    if is_worktree "$wt_dir" || [ -d "$wt_dir" ]; then
        echo "  [+] Removing worktree: $task..."
        git -C "$BASE_DIR" worktree unlock "$wt_dir" 2>/dev/null || true
        git -C "$BASE_DIR" worktree remove --force "$wt_dir" 2>/dev/null || rm -rf "$wt_dir"
        local parent_dir="$(dirname "$wt_dir")"
        while [ "$parent_dir" != "$SWARM_ROOT" ] && [ "$parent_dir" != "/" ] && [ -d "$parent_dir" ]; do
            rmdir "$parent_dir" 2>/dev/null || break
            parent_dir="$(dirname "$parent_dir")"
        done
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
        local tmp_tasks
        tmp_tasks="$(mktemp)"
        local norm_target
        norm_target="$(normalize_task_name "$task")"
        while IFS= read -r line || [ -n "$line" ]; do
            local clean_line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [ -z "$clean_line" ] && continue
            local norm_line="$(normalize_task_name "$clean_line")"
            if [ "$clean_line" = "$task" ] || [ "$clean_line" = "$task_input" ] || [ "$norm_line" = "$norm_target" ] || [ "$norm_line" = "$task" ]; then
                continue
            fi
            echo "$clean_line" >> "$tmp_tasks"
        done < "$TASKS_FILE"
        chmod --reference="$TASKS_FILE" "$tmp_tasks" 2>/dev/null || true
        mv -f "$tmp_tasks" "$TASKS_FILE"
        if [ -f "$TASKS_FILE" ] && ! grep -q '[^[:space:]]' "$TASKS_FILE" 2>/dev/null; then
            rm -f "$TASKS_FILE" 2>/dev/null || true
        fi
    fi

    local swarm_candidates=()
    [ -n "$SWARM_SH" ] && [ -f "$SWARM_SH" ] && swarm_candidates+=("$SWARM_SH")
    if [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/swarm.sh" ]; then
        if [ -z "$SWARM_SH" ] || [ ! "$BASE_DIR/swarm.sh" -ef "$SWARM_SH" ]; then
            swarm_candidates+=("$BASE_DIR/swarm.sh")
        fi
    fi

    for s_file in "${swarm_candidates[@]}"; do
        remove_task_from_swarm_file "$s_file" "$task"
        if [ "$task_input" != "$task" ]; then
            remove_task_from_swarm_file "$s_file" "$task_input"
        fi
    done

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

    local swarm_candidates=()
    [ -n "$SWARM_SH" ] && [ -f "$SWARM_SH" ] && swarm_candidates+=("$SWARM_SH")
    if [ -n "$BASE_DIR" ] && [ -f "$BASE_DIR/swarm.sh" ]; then
        if [ -z "$SWARM_SH" ] || [ ! "$BASE_DIR/swarm.sh" -ef "$SWARM_SH" ]; then
            swarm_candidates+=("$BASE_DIR/swarm.sh")
        fi
    fi

    for s_file in "${swarm_candidates[@]}"; do
        empty_tasks_in_swarm_file "$s_file"
    done

    git -C "$BASE_DIR" worktree prune 2>/dev/null || true
    rm -f "$TASKS_FILE" 2>/dev/null || true
    rmdir "$SWARM_ROOT" 2>/dev/null || true
    echo "All done! Workspace is clean and tidy!"
}
