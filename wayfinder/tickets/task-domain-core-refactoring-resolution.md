---
type: task-resolution
ticket: issue-38
status: resolved
date: 2026-09-08
url: https://github.com/RafaelScharf/SwarmDeck/issues/38
branch: refactor/38-domain-core-swift6
---

# Resolution: Task - Domain Core Refactoring & Strict Swift 6 Concurrency Model

## Question
How do we refine and solidify SwarmDeck's domain models (`Domain/Session.swift`, `Domain/AgentState.swift`, `Domain/AgentPreset.swift`) to enforce strict Swift 6 Sendable conformance, explicit state machine transitions, and complete isolation from UI and POSIX layers?

## Findings & Implementation

1. **Strict Swift 6 Sendable Concurrency & Complete UI/POSIX Decoupling:**
   - Audited and refactored all core models in `Sources/SwarmDeck/Domain/` to ensure 100% `@Sendable` thread-safety across concurrent task and actor boundaries without relying on `@unchecked Sendable`.
   - Stripped all low-level POSIX headers (`sys/types.h`, `pid_t`) and AppKit/SwiftUI dependencies from domain types:
     - Process IDs are represented via pure Swift standard integer types (`Int32`).
     - Visual iconography is specified as abstract symbol identifiers (`iconName: String`) rather than framework-specific image objects.
     - System shell environment harvesting uses standard Foundation `ProcessInfo`.

2. **Formalized `AgentState` State Machine & Invariants:**
   - Refactored `AgentState` (`idle`, `working`, `blocked`, `exited`) into a formal finite state machine with strict transition invariants:
     - **Terminal Invariant:** `.exited` is an immutable terminal state. Once a process terminates, `canTransition(to:)` returns `false` for all subsequent states, and `transition(to:)` throws `AgentStateTransitionError.invalidTransition`. Session respawns must reinitialize a new lifecycle instance.
     - **Active Invariants:** Transitions between `.idle`, `.working`, and `.blocked` are bi-directional and valid upon user commands, tool execution, or confirmation prompts. Any active state can transition into `.exited`.
   - Introduced domain value types for state payloads:
     - `BlockedReason`: Structured, `ExpressibleByStringLiteral`, `Codable`, `Sendable`, and `CustomStringConvertible` reason container with well-known presets (`.confirmationRequired`, `.terminalBell`, `.inputRequired`, `.permissionRequired`).
     - `ProcessExitCode`: Structured, `ExpressibleByIntegerLiteral`, `Codable`, `Sendable`, and `CustomStringConvertible` status container with status inspection (`isSuccess`, `isSignalTerminated`), well-known constants (`.success`, `.failure`, `.sigint`, `.sigterm`, `.sigkill`), and seamless `Int32` equality comparison.
   - Implemented state query predicates (`isTerminal`, `isIdle`, `isWorking`, `isBlocked`, `blockedReason`, `exitCode`).
   - Implemented clean JSON `Codable` encoding/decoding for persistence across app restarts.

3. **Solidified `Session`, `SessionMetadata`, and `SessionId` Aggregate Models:**
   - Refactored `Sources/SwarmDeck/Domain/Session.swift` into a complete domain model suite:
     - `SessionId`: Strongly-typed UUID wrapper with string validation and serialization.
     - `SessionMetadata`: Lightweight, immutable session configuration metadata (`id`, `name`, `preset`, `workingDirectory`, `customEnvironment`, `createdAt`).
     - `Session`: Pure value-type aggregate root entity tracking identity, configuration, `state`, `processId`, `exitCode`, and audit timestamps (`createdAt`, `updatedAt`).
     - Mutating state transition method `session.transition(to:)` enforcing state machine invariants and automatically capturing exit codes.
     - All models conform to `Identifiable`, `Sendable`, `Equatable`, `Hashable`, and `Codable`.

4. **Hardened `AgentPreset` Configuration Model:**
   - Validated standard presets (`.standardShell`, `.claudeCode`, `.aider`, `.antigravity`) and dynamic `.custom(...)` generation.
   - Added `isValid` executable validation logic.
   - Fully enabled `Codable` JSON serialization for future declarative workspace topology persistence (`~/.config/swarmdeck/workspace.json`, Issue #41).

5. **Integrated SPM Test Target & Swift Testing Suite:**
   - Updated `Package.swift` to add `.testTarget(name: "SwarmDeckTests", dependencies: ["SwarmDeck"], path: "Tests/SwarmDeckTests")`.
   - Implemented 26 unit tests using Swift 6 Testing framework (`@Suite`, `@Test`, `#expect`) across:
     - `Tests/SwarmDeckTests/DomainTests/AgentStateTests.swift` (11 tests)
     - `Tests/SwarmDeckTests/DomainTests/AgentPresetTests.swift` (6 tests)
     - `Tests/SwarmDeckTests/DomainTests/SessionTests.swift` (9 tests)

## Test Validation

Both `swift test` and `swift test -Xswiftc -strict-concurrency=complete` run cleanly with 100% test success:

```
Test Suite 'All tests' started at 2026-09-08 17:00:43.766.
Test Suite 'SwarmDeckPackageTests.xctest' started at 2026-09-08 17:00:43.767.
Test Suite 'AgentPresetTests' passed (6 tests, 0 failures).
Test Suite 'AgentStateTests' passed (11 tests, 0 failures).
Test Suite 'SessionTests' passed (9 tests, 0 failures).
Test Suite 'All tests' passed at 2026-09-08 17:00:43.776.
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.008 (0.009) seconds
```

`swift build -Xswiftc -strict-concurrency=complete` compiles with zero warnings or concurrency diagnostic errors.
