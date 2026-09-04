---
type: prototype-resolution
ticket: issue-10
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/10
branch: feat/issue-10-shell-env-harvesting
---

# Resolution: Prototype - macOS Login Shell Environment Harvesting

## Question
How do we asynchronously, safely, and deterministically harvest the user's interactive login shell environment (`PATH`, `nvm`, `asdf`, `mise`, `cargo`, `Homebrew`, and API keys like `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) when SwarmDeck is packaged and launched as a macOS `.app` bundle (via LaunchServices/Dock/Spotlight), preventing agents from failing silently?

## Findings & Implementation

1. **Shell Discovery & Invocation:**
   - Determined user shell using `getpwuid(getuid())?.pointee.pw_shell` with fallback to `ProcessInfo.processInfo.environment["SHELL"]` and `/bin/zsh`.
   - Executed login shell with `/usr/bin/env -0 2>/dev/null || printenv` via `-l -c` (or `-l -i -c`).
   - Using `/usr/bin/env -0` guarantees safe, unambiguous null-delimited (`\0`) variable extraction regardless of internal newlines, equal signs, or formatting.

2. **Timeout Watchdog:**
   - Enforced an asynchronous timeout watchdog using `DispatchSourceTimer` (default 800ms).
   - If the user's shell configuration hangs or stalls on interactive prompts, the subprocess is gracefully terminated and escalated to `SIGKILL`, immediately falling back to process environment and default search paths without blocking UI responsiveness.

3. **Parsing & Default Merging:**
   - Parsed null-delimited tokens and fallback newline-delimited outputs into a typed `[String: String]` dictionary with variable identifier validation.
   - Enforced standard terminal capabilities: `TERM=xterm-256color`, `COLORTERM=truecolor`, and `LANG=en_US.UTF-8`.
   - Guaranteed essential paths in `PATH` (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`).

4. **In-Memory Caching & Startup Integration:**
   - Implemented `cachedEnvironment` inside `ShellEnvironmentHarvester` actor and synced to thread-safe `ProcessEnvironment.cachedHarvestedEnvironment`.
   - Subsequent calls return instantly (<0.1ms).
   - Wired asynchronous background harvesting in `AppDelegate.applicationDidFinishLaunching`.

## Test Validation
- Created automated 31-point validation test suite in `temp/prototypes/test_shell_env_harvesting.swift`.
- Tests covered user shell resolution, null-delimited/multiline parsing, live shell harvesting with CLI tool path discovery, in-memory caching performance (<5ms), sterile `launchd` simulation, and timeout watchdog abort.
- All 31 tests passed with 100% success rate.
