<img width="1920" height="1080" alt="Full HD" src="https://github.com/user-attachments/assets/40021ad0-84e0-40ac-930b-bc327e2a535d" />

# AGYCommando

A swarm orchestration and agent management utility designed exclusively for **Antigravity CLI** (`agy`).

> **Compatibility**: This tool is built specifically for Antigravity CLI (`agy`) only.

## Requirements

- **Antigravity CLI (`agy`)**: AGYCommando is made specifically for Antigravity CLI. Ensure `agy` is installed and accessible in your system's `PATH`.

## Usage

AGYCommando can be used in any project:

1. Clone AGYCommando into your project root:
   ```bash
   cd /path/to/your-project
   git clone https://github.com/LoggingNewMemory/AGYCommando.git
   ```

2. Run scripts using either method:
   - **Navigate to AGYCommando**:
     ```bash
     cd AGYCommando
     ./swarm.sh <task...>
     ```
   - **Run from project root**:
     ```bash
     ./AGYCommando/swarm.sh <task...>
     ```

> **Note**: AGYCommando does not use hardcoded paths and automatically detects the target host repository.

## Updating AGYCommando

To update AGYCommando to the latest version:

- **Standard update**:
  ```bash
  cd AGYCommando && git pull
  ```
  Or directly from your project root:
  ```bash
  git -C AGYCommando pull
  ```

- **Force update (overwrite local changes)**:
  If you modified files (such as `swarm.sh`) and want to discard local edits to match upstream:
  ```bash
  cd AGYCommando && git fetch origin && git reset --hard origin/main
  ```
  Or directly from your project root:
  ```bash
  git -C AGYCommando fetch origin && git -C AGYCommando reset --hard origin/main
  ```

## Autonomous Execution & Permissions Notice

> [!WARNING]
> By default, AGYCommando launches agents with:
> ```bash
> agy --dangerously-skip-permissions
> ```
>
> ### Why does AGYCommando use `--dangerously-skip-permissions`?
> The core goal of running an agent swarm is true autonomy. By skipping interactive permission prompts, you can simply deploy the agent terminal tabs, prompt them with their tasks, and then focus on something else or simply go have a meal—without needing to babysit each agent or manually approve every tool call, file modification, and command.
>
> **Safety & Isolation**:
> - Each agent operates inside an isolated Git worktree (`swarm/<task>`), keeping your main branch and other tasks separate and safe.
> - Always review agent code changes before merging them into your main branch using the interactive test harness: `./swarm.sh test` (or `./test-swarm.sh`).
> - If you prefer interactive approval, you can override the agent command at any time via the `--cmd` flag (e.g. `./swarm.sh --cmd "agy"`) or by setting the `SWARM_AGENT_CMD` environment variable.

---

Support Me: <br />
- [SociaBuzz (Global)](https://sociabuzz.com/kanagawa_yamada/tribe)
- [QRIS (Local/ID)](https://t.me/KLAGen2/1166)
