---
type: prototype-resolution
ticket: issue-4
status: resolved
date: 2026-09-03
url: https://github.com/RafaelScharf/SwarmDeck/issues/4
branch: prototype/multi-session-sidebar
---

# Resolution: Prototype - Sidebar & Multi-Session Architecture

## Question
What is the most robust SwiftUI architecture (Observation vs TCA vs MVVM) for managing multiple background AI sessions simultaneously without UI lag?

## Findings & Resolution
1. **Observation Architecture:**
   - Swift 5.9 / macOS 14+ `@Observable` macro applied to `Session` and `SessionManager` classes on `@MainActor` provides fine-grained, frictionless view updates.
2. **Background Execution:**
   - Detached background read tasks in `PTY` actors feed data to `InMemoryTerminalSession` and `OutputStateDetector` independently of which session is currently selected in the UI.
3. **Ghostty Surface Multiplexing:**
   - `NavigationSplitView` renders `TerminalSurfaceView(context: viewState).id(sessionId)`. The `.id()` modifier forces clean surface teardown and re-attachment when switching tabs, preventing memory leaks and UI lag.
4. **Visual State Indicators:**
   - Sidebar lists dynamically update with status badges (e.g. green spinner for `.working`, red dot for `.blocked`, gray for `.idle`).

## Branch Reference
- Code integrated in branch `prototype/multi-session-sidebar` under `Sources/SwarmDeckPrototype/`.
