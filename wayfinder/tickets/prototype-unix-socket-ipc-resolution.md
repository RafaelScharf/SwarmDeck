---
type: prototype-resolution
ticket: issue-12
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/12
branch: feat/issue-12-unix-socket-ipc
---

# Resolution: Prototype - Unix Domain Socket IPC & CLI Dispatcher

## Question
How do we enable developers to launch and query SwarmDeck agent sessions directly from their existing terminal (`swarmdeck run --preset claude --cwd .`) via a lightweight local Unix Domain Socket IPC server?

## Findings & Implementation

1. **Unix Domain Socket Server (`IPCServer`):**
   - Implemented `IPCServer` actor binding to `/tmp/swarmdeck-$UID.sock`.
   - Used non-blocking Darwin POSIX sockets combined with Grand Central Dispatch `DispatchSourceRead` for asynchronous connection accepting and message processing.
   - Designed a clean newline-delimited JSON-RPC protocol with typed `IPCRequest` and `IPCResponse` models.
   - Supports methods:
     - `ping`: Health check returning "pong".
     - `spawn`: Spawns an agent session by preset (`claude`, `aider`, `agy`, `shell`), custom name, and working directory (`cwd`), optionally activating and focusing the SwarmDeck window.
     - `list`: Returns array of active sessions, names, presets, and states.
     - `terminate`: Terminates an agent session by UUID.
   - Clean shutdown with socket unlink in `stop()`.

2. **CLI Client Helper (`IPCClient` & CLI tool):**
   - Implemented `IPCClient` with connection health checks (`isServerRunning`), connection timeout watchdog, and request/response serialization.
   - Built standalone CLI executable spike `temp/prototypes/swarmdeck_cli.swift` supporting:
     - `swarmdeck ping`
     - `swarmdeck run --preset claude --cwd /path/to/project`
     - `swarmdeck list`
     - `swarmdeck terminate <sessionId>`
   - Provides clear, actionable error messages when SwarmDeck is not running.

3. **Application Lifecycle Integration:**
   - Started `IPCServer.shared` on app launch in `AppDelegate.applicationDidFinishLaunching`.
   - Wired request handler to `SessionManager.shared` on `@MainActor`, synchronizing CLI spawns with the SwiftUI multi-session sidebar.

## Test Validation
- Created comprehensive 19-point automated validation test suite in `temp/prototypes/test_ipc_server.swift`.
- Tested fallback when server is absent, socket binding and creation, bi-directional JSON-RPC method dispatching (`ping`, `spawn`, `list`, `terminate`), invalid method error handling (`-32601`), concurrent client connections (8 parallel clients without deadlock), and clean socket unlink on shutdown.
- All 19 tests passed with 100% success rate.
