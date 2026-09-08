---
type: task-resolution
ticket: issue-41
status: resolved
date: 2026-09-08
url: https://github.com/RafaelScharf/SwarmDeck/issues/41
branch: feat/41-workspace-persistence
---

# Resolution: Task - Declarative Workspace Topology & Crash-Resilient Persistence

## Question
How do we implement a declarative, crash-resilient workspace persistence engine in SwarmDeck that automatically serializes active sessions and metadata to disk, provides atomic POSIX writes with debouncing, recovers safely from unexpected termination or corrupted states, and handles clean application shutdown?

## Findings & Implementation

1. **`WorkspacePersistenceService` Actor & Atomic Storage:**
   - Implemented `WorkspacePersistenceService` in `Sources/SwarmDeck/Services/Persistence/WorkspacePersistenceService.swift` conforming to Swift 6 strict concurrency (`actor`, `@Sendable`).
   - Default persistence path: `~/.config/swarmdeck/workspace.json`. Automatically ensures directory creation if missing.
   - **Atomic Write Pattern:** Writes JSON payload to temporary file (`workspace.json.tmp`) and executes an atomic POSIX file rename (`rename()` via `FileManager.replaceItemAt` / atomic write) to eliminate corrupted or partially-written states if power or process dies mid-write.
   - **Debounced Coalescing:** Implemented a 500ms debounce interval (`scheduleSave`) so rapid UI events (e.g. typing names, sequential session spawns, continuous output) coalesce into a single serialized write, while exposing `saveImmediately()` and `flush()` for synchronous lifecycle events.

2. **Declarative `WorkspaceTopology` Model:**
   - Created pure value type `WorkspaceTopology` (`Sendable, Equatable, Hashable, Codable`):
     - `version`: Topology schema version (currently `1`).
     - `sessions`: Array of pure domain `Session` models (from Issue #38) capturing identity, configuration metadata, working directory, and last known state.
     - `selectedSessionId`: Currently active session UUID.
     - `lastSavedAt`: UTC timestamp of last snapshot.
     - `cleanShutdown`: Boolean flag indicating whether the app shut down gracefully or suffered a crash/kill.

3. **Crash Recovery & Corrupted State Self-Healing:**
   - Implemented `loadWithRecovery()` in `WorkspacePersistenceService`:
     - If `workspace.json` is missing: cleanly initializes a default empty workspace without throwing.
     - If `workspace.json` is zero bytes or contains malformed JSON: safely quarantines the corrupted file into a timestamped backup (`workspace.json.corrupted-<ISO8601>`) and returns an empty topology marked `wasCorrupted: true`, allowing the app to launch into a clean state without crashing.
   - Preserves state across crashes: on launch, if `cleanShutdown == false`, sessions can be inspected or reported as recovered from an unexpected termination.

4. **Auto-Restart Policy & Agent Safety:**
   - Defined `AutoRestartPolicy` enum (`disabled`, `safePresetsOnly`, `allPresets`):
     - `.disabled`: Restores sessions into an `.idle` state without automatically re-executing processes.
     - `.safePresetsOnly` (default): Only restarts presets that are safe to auto-spawn (e.g. standard login shells via `AgentPreset.isSafeForAutoRestart`), leaving autonomous AI agent presets (`claudeCode`, `aider`, `antigravity`) stopped so they do not unintentionally run commands or consume tokens on startup.
     - `.allPresets`: Auto-restarts all persisted sessions.

5. **`SessionStore` & Lifecycle Integration:**
   - Added `AgentSession.toSession() -> Session` conversion mapping in `SessionStore.swift`.
   - Wired `persistWorkspace()` hook across all session lifecycle events: `addSession`, `closeSession`, `terminateSession`, `restartSession`, `renameSession`, and `selectSession`.
   - Added `restoreWorkspace(policy:)` to restore persisted sessions on launch, selecting the previously focused session.
   - Updated `MainView.swift` `.task` to invoke `restoreWorkspace()` on startup, falling back to default welcome sessions only if the workspace is newly initialized.
   - Added `AppDelegate.applicationWillTerminate` hook invoking `SessionStore.shared.shutdown()` to terminate child processes and write `cleanShutdown = true` before process exit.

6. **Comprehensive Unit Testing Suite:**
   - Implemented 12 unit tests using Swift 6 Testing framework in `Tests/SwarmDeckTests/PersistenceTests/WorkspacePersistenceTests.swift`:
     - Full JSON serialization & roundtrip across all 4 `AgentState` cases.
     - Atomic write verification (no dangling `.tmp` file).
     - Debounced save coalescing (5 rapid updates collapse to single write).
     - Immediate flush execution.
     - Corrupted file recovery with quarantine backup.
     - Zero-byte empty file recovery.
     - Missing file clean initialization.
     - Clean shutdown flag recording.
     - `AgentPreset.isSafeForAutoRestart` safety verification.
     - `AutoRestartPolicy` enum validation.
     - `AgentSession.toSession()` domain conversion validation.
     - `SessionStore.restoreWorkspace()` with disabled auto-restart.

## Test Validation

Full test suite execution (`swift test` with CommandLineTools frameworks):

```
✔ Test run with 38 tests in 4 suites passed after 0.377 seconds.
- AgentPreset Domain Model Tests: 6 passed
- AgentState Domain Model Tests: 11 passed
- Session & SessionMetadata Domain Model Tests: 9 passed
- Workspace Persistence & Crash Recovery Tests: 12 passed
```

`swift build` compiles cleanly with zero errors.
