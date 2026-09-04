# SwarmDeck Prototypes & Technical Spikes

This directory temporarily archives the standalone spike scripts, mock runners, and low-level tests used to validate core technical hypotheses during the Wayfinder exploratory phase before production implementation.

## Prototype Inventory

### 1. Minimal SwiftUI PTY App (Issue #2 / `prototype/issue-2`)
* **Goal**: Validate low-level PTY allocation, job control, signals (`Ctrl+C`), and integration with `libghostty-spm`.
* **Scripts**:
  * [`test_openpty.swift`](test_openpty.swift): Initial POSIX `openpty()` test with `Foundation.Process`.
  * [`test_forkpty.swift`](test_forkpty.swift): Validated `forkpty()` allocating a controlling terminal (`TIOCSCTTY`) and session leadership for shells.
  * [`test_pty.swift`](test_pty.swift): Validated `PTY` actor asynchronous master I/O using `@testable import SwarmDeckPrototype`.
  * [`run_pty_test.swift`](run_pty_test.swift) & [`run_pty_test2.swift`](run_pty_test2.swift): Standalone terminal I/O streaming runners.
* **Key Finding**: `openpty()` with `Process()` fails to establish job control and breaks signal forwarding. Must use `forkpty()` directly with Darwin C APIs.

### 2. Agent State Detection Engine (Issue #3 / `prototype/issue-3-state-detector`)
* **Goal**: Validate the Multi-Tier Detection Pipeline (debounce, ANSI stripping, carriage return overwrites, OSC 133 semantic prompts, bell alert, regexes).
* **Scripts**:
  * [`prototype_state_detector.swift`](prototype_state_detector.swift): Interactive CLI simulator and test harness. Simulates Aider, Claude Code, spinners (`\r`), permission approval prompts (`(y/n)`), and OSC 133 prompt markers.
* **Key Finding**: 250ms debounce settles LLM streaming gaps; isolating the tail segment after `\r` correctly reads spinner overwrites.

### 3. Sidebar & Multi-Session Architecture (Issue #4 / `prototype/multi-session-sidebar`)
* **Goal**: Validate macOS 14+ `@Observable` with `NavigationSplitView` for multiple concurrent background sessions.
* **Branch**: `prototype/multi-session-sidebar` (contains the prototype app in `Sources/SwarmDeckPrototype`).
* **Key Finding**: `.id(sessionId)` on `TerminalSurfaceView` allows instant switching between sessions without memory leaks or main-thread lag.

### 4. Process Lifecycle Supervisor & Configurable Spawning (Issue #5 / `feat/issue-5-process-supervisor`)
* **Goal**: Validate background PTY process supervision (exit detection via `DispatchSourceProcess`, zombie prevention via automatic `waitpid` reaping, graceful termination with SIGTERM escalation to SIGKILL) and configurable agent spawning (`AgentPreset`, custom cwd, enriched PATH and environment inheritance).
* **Scripts**:
  * [`test_lifecycle_supervisor.swift`](test_lifecycle_supervisor.swift): Automated 33-point validation test suite covering preset models, binary resolution (`claude`, `aider`, `agy`), exit status decoding, zombie reaping verification (`waitpid` returns -1 `ECHILD`), graceful signal termination, and PTY execution with custom CWD and environment.
* **Key Finding**: Pre-allocating `argv` and `envp` pointers before `forkpty` guarantees async-signal safety in the child without heap allocation/locks. `DispatchSourceProcess` monitoring `.exit` combined with non-blocking POSIX `waitpid` reliably prevents zombie processes and updates agent state to `.exited(code)`.
