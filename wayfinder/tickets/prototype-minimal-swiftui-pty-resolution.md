---
type: prototype-resolution
ticket: issue-2
status: resolved
date: 2026-09-03
url: https://github.com/RafaelScharf/SwarmDeck/issues/2
branch: prototype/issue-2
artifacts: temp/prototypes/
---

# Resolution: Prototype - Minimal SwiftUI PTY App

## Question
How does the minimal end-to-end integration of `libghostty` and Swift Concurrency PTY management look in practice?

## Findings & Resolution
1. **Low-Level PTY Allocation:**
   - Testing showed that `openpty()` combined with `Foundation.Process` fails to attach a controlling terminal (`TIOCSCTTY`) properly, preventing interactive shells (like `zsh`) from handling job control and signals (`Ctrl+C`).
   - The solution adopted was `forkpty(&masterFD, nil, nil, nil)` inside a dedicated `PTY` Swift actor, configuring environment variables and calling `execve("/bin/zsh", ...)` directly in the child process.
2. **Ghostty Integration:**
   - Utilized `Lakr233/libghostty-spm` (`GhosttyTerminal` package).
   - Wrapped the PTY master I/O in `InMemoryTerminalSession(write:resize:)` and passed data via `.receive(data)` to `TerminalSurfaceView`.
3. **Focus & Interaction:**
   - Required window key activation (`makeKeyAndOrderFront`) and explicit terminal focus (`viewState.requestFocus()`) for immediate keyboard input upon launch.

## Archived Spike Artifacts
- `temp/prototypes/test_openpty.swift`
- `temp/prototypes/test_forkpty.swift`
- `temp/prototypes/test_pty.swift`
- `temp/prototypes/run_pty_test.swift`
- `temp/prototypes/run_pty_test2.swift`
