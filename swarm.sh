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

set -e

TASKS=(
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""
CLI_TASKS=()
CUSTOM_AGENT_CMD=""
FORCE_SPAWN=false

show_help() {
    cat << 'EOF'
Usage: swarm.sh [OPTIONS] [TASK_NAME ...]
       swarm.sh test [OPTIONS]
       swarm.sh clean [OPTIONS]

Spawns isolated Git worktrees and terminal tabs running autonomous AI agents (agy).

Options:
  -C, --repo <PATH>       Target git repository path (default: auto-detected project)
      --cmd <COMMAND>     Custom agent command (default: $SWARM_AGENT_CMD or 'agy --dangerously-skip-permissions')
  -f, --force             Force spawn terminals even if workspace already exists
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
        -f|--force)
            FORCE_SPAWN=true
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

clear 2>/dev/null || true

if [ -z "$TARGET_DIR" ] && [ ${#CLI_TASKS[@]} -gt 0 ]; then
    if [ -d "${CLI_TASKS[0]}" ] && git -C "${CLI_TASKS[0]}" rev-parse --show-toplevel &>/dev/null; then
        TARGET_DIR="${CLI_TASKS[0]}"
        CLI_TASKS=("${CLI_TASKS[@]:1}")
    fi
fi

source "$SCRIPT_DIR/lib/core.sh"
init_swarm_env
source "$SCRIPT_DIR/lib/terminal.sh"

AGENT_CMD="${CUSTOM_AGENT_CMD:-${SWARM_AGENT_CMD:-agy --dangerously-skip-permissions}}"

# Extract line-by-line task entries from TASKS=( ... ) in swarm.sh
FILE_TASKS=()
if [ -n "$SWARM_SH" ] && [ -f "$SWARM_SH" ]; then
    in_block=false
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*TASKS=\((.*)\)[[:space:]]*$ ]]; then
            inline_items=()
            eval "inline_items=(${BASH_REMATCH[1]})" 2>/dev/null || read -ra inline_items <<< "${BASH_REMATCH[1]}"
            for raw_item in "${inline_items[@]}"; do
                [ -n "$raw_item" ] && [[ ! "$raw_item" =~ ^# ]] && FILE_TASKS+=("$raw_item")
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
            item_no_comment="${line%%#*}"
            item="$(echo "$item_no_comment" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'\'']//' -e 's/["'\'']$//')"
            if [ -n "$item" ] && [[ ! "$item" =~ ^# ]]; then
                FILE_TASKS+=("$item")
            fi
        fi
    done < "$SWARM_SH"
fi

if [ ${#CLI_TASKS[@]} -gt 0 ]; then
    RAW_TASKS=("${CLI_TASKS[@]}")
elif [ ${#FILE_TASKS[@]} -gt 0 ]; then
    RAW_TASKS=("${FILE_TASKS[@]}")
elif [ ${#TASKS[@]} -gt 0 ]; then
    RAW_TASKS=("${TASKS[@]}")
elif [ -f "$TASKS_FILE" ]; then
    RAW_TASKS=()
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue
        RAW_TASKS+=("$line")
    done < "$TASKS_FILE"
else
    RAW_TASKS=()
fi

if [ ${#RAW_TASKS[@]} -eq 0 ]; then
    echo "Target Project: $REPO_NAME ($BASE_DIR)"
    echo "No swarm tasks specified."
    read -rp "Enter task name(s) separated by spaces (e.g. auth ui backend): " input_tasks
    read -ra PROMPTED_TASKS <<< "$input_tasks"
    if [ ${#PROMPTED_TASKS[@]} -eq 0 ]; then
        echo "No tasks provided. Aborting."
        exit 1
    fi
    RAW_TASKS=("${PROMPTED_TASKS[@]}")
fi

# Normalize task names (spaces/slashes to hyphens for valid git refs) and deduplicate
TASKS=()
for t in "${RAW_TASKS[@]}"; do
    clean_task="$(normalize_task_name "$t")"
    [ -z "$clean_task" ] && continue
    found=false
    for existing in "${TASKS[@]}"; do
        if [ "$existing" = "$clean_task" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        TASKS+=("$clean_task")
    fi
done

mkdir -p "$SWARM_ROOT"
touch "$TASKS_FILE"

for task in "${TASKS[@]}"; do
    if ! grep -qFx "$task" "$TASKS_FILE" 2>/dev/null; then
        echo "$task" >> "$TASKS_FILE"
    fi
done

echo "=========================================================="
echo " Starting Agentic Swarm for: $REPO_NAME"
echo " Target Repository : $BASE_DIR"
echo " Swarm Root        : $SWARM_ROOT"
echo " Tasks             : ${TASKS[*]}"
echo "=========================================================="

NEW_SPAWNED=0
SKIPPED_EXISTING=0

for task in "${TASKS[@]}"; do
    WORKTREE_DIR="$SWARM_ROOT/$task"
    BRANCH_NAME="swarm/$task"

    echo "----------------------------------------------------------"
    echo "Checking workspace for task: [$task]"

    is_new=false
    if is_worktree "$WORKTREE_DIR"; then
        if [ "$FORCE_SPAWN" = true ]; then
            echo "  [*] Worktree directory exists, force re-spawning terminal: $WORKTREE_DIR"
        else
            echo "  [*] Workspace already active at: $WORKTREE_DIR"
            echo "      (Skipping terminal spawn; use --force to re-spawn)"
            ((SKIPPED_EXISTING++)) || true
            continue
        fi
    else
        if [ -d "$WORKTREE_DIR" ]; then
            rm -rf "$WORKTREE_DIR"
        fi
        is_new=true
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

    launch_terminal "$WORKTREE_DIR" "$task" "$BRANCH_NAME" "$AGENT_CMD"
    ((NEW_SPAWNED++)) || true
done

echo "----------------------------------------------------------"
if [ "$NEW_SPAWNED" -gt 0 ]; then
    echo "$NEW_SPAWNED agent(s) dispatched!"
fi
if [ "$SKIPPED_EXISTING" -gt 0 ]; then
    echo "$SKIPPED_EXISTING workspace(s) already active (skipped duplicate terminal spawn)."
fi
echo "To test/merge changes: run './test-swarm.sh' (or 'swarm.sh test')"
echo "To clean up: run './clean.sh' (or 'swarm.sh clean')"
