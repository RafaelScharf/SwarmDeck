---
type: task-resolution
ticket: issue-5
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/5
branch: feat/issue-5-process-supervisor
---

# Resolution: Task - Process Lifecycle Supervisor & Configurable Spawning

## Question
How do we ensure robust background PTY process supervision (detecting exits, preventing zombies, handling signals) while supporting configurable agent spawning (presets, custom cwd, environment variables)?

## Findings & Implementation

1. **Process Lifecycle Monitoring & Zombie Prevention:**
   - Implemented `ProcessLifecycleSupervisor` encapsulating `DispatchSourceProcess` monitoring `.exit` on the child PID spawned by `forkpty`.
   - On process termination, `waitpid(pid, &status, 0)` is invoked immediately, ensuring exited children are reaped and no zombie processes remain (verified via automated test suite where subsequent `waitpid` calls return `-1` with `errno == ECHILD`).
   - Decoded POSIX exit status: distinguishes between normal exit (`WIFEXITED` -> `(status >> 8) & 0xFF`) and signal termination (`WIFSIGNALED` -> `128 + signal`).
   - Cleanly closes the master file descriptor (`close(masterFD)`) and transitions `Session.state` to `.exited(code: exitCode)`.

2. **Clean Signal Handling & Termination:**
   - Implemented `terminate(gracePeriod:)` on `ProcessLifecycleSupervisor` and `PTY`: sends `SIGTERM` first for graceful shutdown, polling over a configurable grace period (default 1500ms), and automatically escalates to `SIGKILL` if the child remains unresponsive.
   - Child process explicitly resets signal handlers (`SIGTERM`, `SIGINT`, `SIGQUIT`, `SIGHUP`, `SIGPIPE`) to `SIG_DFL` before `execve` so signal dispositions are clean.
   - Pre-allocated `argv` and `envp` pointers in parent before `forkpty` to guarantee async-signal safety in the child without heap allocation or mutex contention.

3. **Configurable Agent Spawning:**
   - Defined `AgentPreset` model with built-in presets for:
     - Standard Shell (`/bin/zsh -l`)
     - Claude Code (`claude`)
     - Aider (`aider`)
     - Antigravity (`agy`)
     - Custom command (`AgentPreset.custom(...)`)
   - Implemented `ProcessEnvironment`:
     - Resolves executables across `PATH` and common macOS agent locations (`~/.local/bin`, `/opt/homebrew/bin`, `~/.cargo/bin`, `~/.npm-global/bin`).
     - Enriches environment with standard terminal defaults (`TERM=xterm-256color`, `COLORTERM=truecolor`, `LANG=en_US.UTF-8`) while inheriting all user shell variables and API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).
     - Supports custom working directory (`cwd`) via `chdir` in child process.

4. **UI Integration:**
   - Updated `ContentView` toolbar `+` button with a preset picker menu and custom command creation sheet.
   - Added visual badges for `.exited(code)` and PID display in the sidebar.
   - Added context menus for terminating running processes and closing sessions.

## Test Validation
- Created comprehensive 33-point validation test suite in `temp/prototypes/test_lifecycle_supervisor.swift`.
- All 33 tests passed with 100% success rate.
