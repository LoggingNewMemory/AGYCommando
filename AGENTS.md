# Agent Instructions

All LLMs and AI agents working on this project must consult and strictly adhere to the guidelines and instructions provided in the [`Skill`](Skill/) folder before taking actions or executing commands.

> **Note**: Documents in the [`Skill`](Skill/) folder are strict behavioral constraints and instructions for **LLMs only**. (Developers must figure things out on their own).

## Core LLM Rules

- **Universal Portability (No Hardcoded Paths)**: AGYCommando is designed to be cloned and used in any target project repository. Never hardcode paths, usernames, or project directories into scripts, configuration files, or codebase changes. All paths must be dynamically resolved.
- **Dual Execution Support**: Ensure support for both invocation patterns:
  1. Changing directory into `AGYCommando`: `cd AGYCommando && ./Scripts/...`
  2. Directly from the host project root: `./AGYCommando/Scripts/...`

## Skill Files (LLM Only)

- [`GitBasic.md`](Skill/GitBasic.md): Strict Git rules (no git commit unless commanded; keep everything unstaged for developer review).
- [`Usage.md`](Skill/Usage.md): Usage model, execution patterns, and strict dynamic path requirements.
