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


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

source "$SCRIPT_DIR/lib/core.sh"
init_swarm_env
source "$SCRIPT_DIR/lib/cleanup.sh"

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
        if is_worktree "$wt_dir"; then
            wt_status="Exists"
        elif [ -d "$wt_dir" ]; then
            wt_status="Invalid"
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
