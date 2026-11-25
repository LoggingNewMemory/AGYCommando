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
CUSTOM_AGENT_CMD=""
TAB_IDX=0

show_help() {
    cat << 'EOF'
Usage: commando.sh [OPTIONS]

Unified interactive control center for AGYCommando.
Switch between Swarm, Test/Merge, and Clean menus without exiting.

Options:
  -C, --repo <PATH>       Target git repository path (default: auto-detected project)
      --cmd <COMMAND>     Custom agent command (default: $SWARM_AGENT_CMD or 'agy --dangerously-skip-permissions')
  -t, --tab <NAME>        Initial tab: swarm, test, or clean (default: swarm)
  -h, --help              Show this help message

Navigation:
  a / A                   Previous menu tab
  d / D                   Next menu tab
  u / U                   Update AGYCommando (normal or force git pull)
  q / Q                   Quit commando.sh
EOF
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
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
        -t|--tab)
            shift
            case "${1,,}" in
                swarm) TAB_IDX=0 ;;
                test|merge) TAB_IDX=1 ;;
                clean) TAB_IDX=2 ;;
            esac
            ;;
        --tab=*)
            tab_arg="${1#*=}"
            case "${tab_arg,,}" in
                swarm) TAB_IDX=0 ;;
                test|merge) TAB_IDX=1 ;;
                clean) TAB_IDX=2 ;;
            esac
            ;;
        -h|--help)
            show_help
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
source "$SCRIPT_DIR/lib/cleanup.sh"

AGENT_CMD="${CUSTOM_AGENT_CMD:-${SWARM_AGENT_CMD:-agy --dangerously-skip-permissions}}"
CONFLICT_MODE="theirs"
TABS=("SWARM" "TEST / MERGE" "CLEAN")

pause_prompt() {
    echo ""
    read -rp "Press Enter to continue..." _ || return 1
}

render_header() {
    local tab_bar=""
    for i in "${!TABS[@]}"; do
        if [ "$i" -eq "$TAB_IDX" ]; then
            tab_bar="${tab_bar} [ ${TABS[$i]} ]"
        else
            tab_bar="${tab_bar}   ${TABS[$i]}  "
        fi
    done

    echo "=========================================================="
    echo " AGYCommando | Repo: $REPO_NAME ($BASE_DIR)"
    echo "----------------------------------------------------------"
    echo "$tab_bar"
    echo " Nav: [A] Prev   [D] Next   [u] Update   [q] Quit"
    echo "=========================================================="
}

update_agycommando() {
    echo ""
    echo "=== UPDATE AGYCOMMANDO ==="
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo "  Error: AGYCommando directory is not a Git repository ($SCRIPT_DIR)."
        pause_prompt || return 1
        return 0
    fi

    local branch
    branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")"
    [ "$branch" = "HEAD" ] && branch="main"

    echo "  Location : $SCRIPT_DIR"
    echo "  Branch   : $branch"
    echo "----------------------------------------------------------"
    echo "  [1] Normal update (git pull)"
    echo "  [2] Force update  (discard local edits, reset to origin/$branch)"
    echo "  [b] Back"
    echo "=========================================================="

    local u_choice
    read -rp "Select update mode (1/2/b): " u_choice || return 1
    case "$u_choice" in
        1)
            echo "Running normal update..."
            git -C "$SCRIPT_DIR" pull
            pause_prompt || return 1
            ;;
        2)
            local confirm_force
            read -rp "Discard local changes in AGYCommando and reset to origin/$branch? (y/N): " confirm_force || return 1
            if [[ "$confirm_force" =~ ^[Yy]$ ]]; then
                echo "Running force update..."
                git -C "$SCRIPT_DIR" fetch origin && git -C "$SCRIPT_DIR" reset --hard "origin/$branch"
                pause_prompt || return 1
            fi
            ;;
        b|B|"")
            ;;
        *)
            echo "Unrecognized option!"
            sleep 1
            ;;
    esac
    return 0
}

nav_prev() {
    TAB_IDX=$(( (TAB_IDX - 1 + ${#TABS[@]}) % ${#TABS[@]} ))
}

nav_next() {
    TAB_IDX=$(( (TAB_IDX + 1) % ${#TABS[@]} ))
}

get_max_task_len() {
    local max_len=14
    for t in "${TASKS[@]}"; do
        if [ ${#t} -gt "$max_len" ]; then
            max_len=${#t}
        fi
    done
    echo "$max_len"
}

run_swarm_tab() {
    echo ""
    echo "=== SWARM LAUNCHER ==="
    echo "  Agent Command : $AGENT_CMD"
    echo "  Swarm Root    : $SWARM_ROOT"
    echo "----------------------------------------------------------"

    if [ ${#TASKS[@]} -eq 0 ]; then
        echo "  No tasks registered yet."
    else
        local max_len
        max_len="$(get_max_task_len)"
        for i in "${!TASKS[@]}"; do
            local t="${TASKS[$i]}"
            local wt_dir="$SWARM_ROOT/$t"
            local status="Not Spawned"
            if is_worktree "$wt_dir"; then
                status="Active Worktree"
            elif [ -d "$wt_dir" ]; then
                status="Invalid Dir"
            fi
            printf "  [%d] Spawn/Re-spawn %-${max_len}s (%s)\n" "$((i+1))" "$t" "$status"
        done
    fi

    echo "----------------------------------------------------------"
    echo "  [n]   Spawn new task(s)"
    echo "  [f]   Force re-spawn all existing tasks"
    echo "  [c]   Change agent command"
    echo "  [u]   Update AGYCommando"
    echo "  [a/d] Prev / Next menu"
    echo "  [q]   Quit"
    echo "=========================================================="

    local choice
    read -rp "Swarm action: " choice || return 1

    case "$choice" in
        "")
            ;;
        a|A)
            nav_prev
            ;;
        d|D)
            nav_next
            ;;
        u|U)
            update_agycommando || return 1
            ;;
        q|Q)
            return 1
            ;;
        n|N)
            local input_tasks
            read -rp "Enter task name(s) separated by spaces: " input_tasks || return 1
            local -a new_tasks=()
            read -ra new_tasks <<< "$input_tasks"
            if [ ${#new_tasks[@]} -gt 0 ]; then
                "$SCRIPT_DIR/swarm.sh" -C "$BASE_DIR" --cmd "$AGENT_CMD" "${new_tasks[@]}"
                pause_prompt || return 1
            else
                echo "No tasks entered."
                sleep 1
            fi
            ;;
        f|F)
            if [ ${#TASKS[@]} -eq 0 ]; then
                echo "No existing tasks to spawn."
                sleep 1
            else
                "$SCRIPT_DIR/swarm.sh" -C "$BASE_DIR" --cmd "$AGENT_CMD" --force "${TASKS[@]}"
                pause_prompt || return 1
            fi
            ;;
        c|C)
            local new_cmd
            read -rp "Enter new agent command (blank to keep current): " new_cmd || return 1
            if [ -n "$new_cmd" ]; then
                AGENT_CMD="$new_cmd"
                echo "Agent command updated."
                sleep 1
            fi
            ;;
        [1-9]*)
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((choice - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#TASKS[@]}" ]; then
                    "$SCRIPT_DIR/swarm.sh" -C "$BASE_DIR" --cmd "$AGENT_CMD" --force "${TASKS[$idx]}"
                    pause_prompt || return 1
                else
                    echo "Invalid number!"
                    sleep 1
                fi
            else
                echo "Unrecognized option!"
                sleep 1
            fi
            ;;
        *)
            echo "Unrecognized option!"
            sleep 1
            ;;
    esac
    return 0
}

run_test_tab() {
    echo ""
    echo "=== ZERO-CONFLICT SWARM MERGE & TEST ==="
    echo "  Current Mode: [$CONFLICT_MODE] (Type 'm' to switch mode)"
    echo "----------------------------------------------------------"

    if [ ${#TASKS[@]} -eq 0 ]; then
        echo "  No swarm tasks found for $REPO_NAME."
        echo "  Switch to SWARM tab (press A) to spawn tasks."
    else
        local max_len
        max_len="$(get_max_task_len)"
        for i in "${!TASKS[@]}"; do
            local t="${TASKS[$i]}"
            local wt_dir="$SWARM_ROOT/$t"
            local status_badge="Empty"
            if is_worktree "$wt_dir"; then
                prepare_worktree_diff "$wt_dir"
                local base_commit
                base_commit="$(get_base_commit "$wt_dir")"
                if [ -n "$base_commit" ]; then
                    local changes_count
                    changes_count=$(git -C "$wt_dir" diff --name-only "$base_commit" -- . ':(exclude)node_modules' ':(exclude).venv' ':(exclude)venv' ":(exclude)$TOOL_FOLDER_NAME" 2>/dev/null | sed '/^\s*$/d' | wc -l)
                    if [ "$changes_count" -gt 0 ]; then
                        status_badge="$changes_count files changed"
                    elif is_task_merged "$wt_dir"; then
                        status_badge="Already Merged"
                    fi
                fi
            elif [ -d "$wt_dir" ]; then
                status_badge="Invalid"
            else
                status_badge="Missing"
            fi
            printf "  [%d] Pull %-${max_len}s (%s)\n" "$((i+1))" "$t" "$status_badge"
        done
    fi

    echo "----------------------------------------------------------"
    echo "  [all] Pull ALL tasks into Main Tree"
    echo "  [m]   Switch Merge Mode (union / theirs / force)"
    echo "  [v]   Undo / Revert 1 task from Main Tree"
    echo "  [s]   View file change details per agent"
    echo "  [r]   Reset Main Tree (clean untracked and discard changes)"
    echo "  [u]   Update AGYCommando"
    echo "  [a/d] Prev / Next menu"
    echo "  [q]   Quit"
    echo "=========================================================="

    local choice
    read -rp "Test/Merge action: " choice || return 1

    case "$choice" in
        "")
            ;;
        a|A)
            nav_prev
            ;;
        d|D)
            nav_next
            ;;
        u|U)
            update_agycommando || return 1
            ;;
        q|Q)
            return 1
            ;;
        all|ALL)
            if [ ${#TASKS[@]} -eq 0 ]; then
                echo "No tasks available."
                sleep 1
            else
                echo "Pulling all tasks sequentially..."
                for t in "${TASKS[@]}"; do
                    apply_task "$t"
                done
                pause_prompt || return 1
            fi
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
            sleep 1
            ;;
        v|V)
            if [ ${#TASKS[@]} -eq 0 ]; then
                echo "No tasks available."
                sleep 1
            else
                local u_choice
                read -rp "Enter task number to revert (1-${#TASKS[@]}): " u_choice || return 1
                if [[ "$u_choice" =~ ^[0-9]+$ ]]; then
                    local u_idx=$((u_choice - 1))
                    if [ "$u_idx" -ge 0 ] && [ "$u_idx" -lt "${#TASKS[@]}" ]; then
                        unapply_task "${TASKS[$u_idx]}"
                    else
                        echo "Invalid number!"
                    fi
                else
                    echo "Invalid number!"
                fi
                pause_prompt || return 1
            fi
            ;;
        s|S)
            if [ ${#TASKS[@]} -eq 0 ]; then
                echo "No tasks available."
                sleep 1
            else
                show_summary
                pause_prompt || return 1
            fi
            ;;
        r|R)
            local confirm
            read -rp "Are you sure you want to reset all uncommitted changes in Main Tree? (y/N): " confirm || return 1
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                git -C "$BASE_DIR" reset --hard HEAD
                git -C "$BASE_DIR" clean -fd -e "$TOOL_FOLDER_NAME"
                echo "Main Tree is clean again! (Original code in Swarm worktrees remains 100% safe!)"
                pause_prompt || return 1
            fi
            ;;
        [1-9]*)
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((choice - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#TASKS[@]}" ]; then
                    apply_task "${TASKS[$idx]}"
                    pause_prompt || return 1
                else
                    echo "Invalid number!"
                    sleep 1
                fi
            else
                echo "Unrecognized option!"
                sleep 1
            fi
            ;;
        *)
            echo "Unrecognized option!"
            sleep 1
            ;;
    esac
    return 0
}

run_clean_tab() {
    echo ""
    echo "=== SWARM CLEANUP ==="
    echo "----------------------------------------------------------"

    if [ ${#TASKS[@]} -eq 0 ]; then
        echo "  No swarm tasks found for $REPO_NAME."
    else
        local max_len
        max_len="$(get_max_task_len)"
        for i in "${!TASKS[@]}"; do
            local t="${TASKS[$i]}"
            local wt_dir="$SWARM_ROOT/$t"
            local branch_name="swarm/$t"

            local wt_status="Missing"
            if is_worktree "$wt_dir"; then
                wt_status="Exists"
            elif [ -d "$wt_dir" ]; then
                wt_status="Invalid"
            fi

            local br_status="Missing"
            if git -C "$BASE_DIR" show-ref --verify --quiet "refs/heads/$branch_name"; then
                br_status="Exists"
            fi

            printf "  [%d] %-${max_len}s (Worktree: %-9s | Branch: %s)\n" "$((i+1))" "$t" "$wt_status" "$br_status"
        done
    fi

    echo "----------------------------------------------------------"
    echo "  [all] Clean ALL tasks at once"
    echo "  [u]   Update AGYCommando"
    echo "  [a/d] Prev / Next menu"
    echo "  [q]   Quit"
    echo "=========================================================="

    local choice
    read -rp "Cleanup action: " choice || return 1

    case "$choice" in
        "")
            ;;
        a|A)
            nav_prev
            ;;
        d|D)
            nav_next
            ;;
        u|U)
            update_agycommando || return 1
            ;;
        q|Q)
            return 1
            ;;
        all|ALL)
            if [ ${#TASKS[@]} -eq 0 ]; then
                echo "No tasks to clean."
                sleep 1
            else
                local confirm_all
                read -rp "Are you sure you want to clean ALL tasks? (y/N): " confirm_all || return 1
                if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                    clean_all true
                    pause_prompt || return 1
                fi
            fi
            ;;
        [1-9]*)
            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((choice - 1))
                if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#TASKS[@]}" ]; then
                    clean_task "${TASKS[$idx]}" true
                    pause_prompt || return 1
                else
                    echo "Invalid number!"
                    sleep 1
                fi
            else
                echo "Unrecognized option!"
                sleep 1
            fi
            ;;
        *)
            echo "Unrecognized option!"
            sleep 1
            ;;
    esac
    return 0
}

while true; do
    clear 2>/dev/null || true
    load_tasks
    render_header

    case "$TAB_IDX" in
        0) run_swarm_tab || break ;;
        1) run_test_tab || break ;;
        2) run_clean_tab || break ;;
    esac
done

echo "Exiting AGYCommando."
