# AGYCommando

A swarm orchestration and agent management utility for multi-agent workflows.

<div align="center">

---

## Get the Fuck Out "Artist"
### This is NOT your division

If you an Anti AI people who somehow discovered this Repo. Also Get out  
GitHub is **NOT** your place. You're not welcomed here. Leave immediately.

---

</div>

## Usage

AGYCommando can be used in any project:

1. Clone AGYCommando into your project root:
   ```bash
   cd /path/to/your-project
   git clone <AGYCommando-URL> AGYCommando
   ```

2. Run scripts using either method:
   - **Navigate to AGYCommando**:
     ```bash
     cd AGYCommando
     ./Scripts/swarm.sh <task...>
     ```
   - **Run from project root**:
     ```bash
     ./AGYCommando/Scripts/swarm.sh <task...>
     ```

> **Note**: AGYCommando does not use hardcoded paths and automatically detects the target host repository.

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
> - Always review agent code changes before merging them into your main branch using the interactive test harness: `./Scripts/swarm.sh test` (or `./Scripts/test-swarm.sh`).
> - If you prefer interactive approval, you can override the agent command at any time via the `--cmd` flag (e.g. `./Scripts/swarm.sh --cmd "agy"`) or by setting the `SWARM_AGENT_CMD` environment variable.

---

Support Me: <br />
- [SociaBuzz (Global)](https://sociabuzz.com/kanagawa_yamada/tribe)
- [QRIS (Local/ID)](https://t.me/KLAGen2/1166)
