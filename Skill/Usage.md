# AGYCommando Usage & Portability Guidelines (LLM Only)

> **Notice**: This document contains strict operational guidelines and behavioral constraints for LLMs and AI agents only. (Developers must figure things out on their own).

## Context: How AGYCommando is Used

AGYCommando is cloned and used inside arbitrary host projects:

1. **Inside a target project root** (e.g., `/path/to/any-project`):
   ```bash
   git clone <AGYCommando-URL> AGYCommando
   ```
2. **Dual Execution Models**:
   - Running from inside AGYCommando: `cd AGYCommando && ./Scripts/...`
   - Running directly from the host project root: `./AGYCommando/Scripts/...`

## Strict LLM Rules

- **No Hardcoded Paths**:
  - Never hardcode absolute file paths, machine-specific paths (e.g., `/home/...`), usernames, or fixed project names in any scripts, configurations, or generated code.
  - All paths must be dynamically resolved relative to the host repository or the script's directory.
  - AGYCommando must be able to run in any project environment out-of-the-box.
- **Dual Execution Compatibility**:
  - Any commands, scripts, or modifications created or executed by the LLM must seamlessly support both invocation patterns (`cd AGYCommando && ./Scripts/...` or `./AGYCommando/Scripts/...`).
