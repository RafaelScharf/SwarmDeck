# Wayfinder Map: SwarmDeck

## Destination

A native macOS SwiftUI application embedding `libghostty` to multiplex and manage background PTY processes for AI coding agents, providing sidebar navigation and system notifications for agent state changes.

## Notes

- **Domain:** macOS native development (SwiftUI), Terminal emulation, Process Management (PTY).
- **Core Tech:** Swift 6 Concurrency, libghostty-spm (Zig/Metal), UserNotifications.
- **Goal:** Zero WebView overhead, minimal latency, robust background execution.
- All core technical spikes (#2, #3, #4) have completed. Current phase is executing the implementation roadmap.

## Decisions so far

- [Prototype: Minimal SwiftUI PTY App](https://github.com/RafaelScharf/SwarmDeck/issues/2) — Embedded `libghostty-spm` via `InMemoryTerminalSession` and switched to `forkpty()` inside a Swift Actor for controlling terminal (`TIOCSCTTY`), job control, and signal handling.
- [Prototype: Agent State Detection Engine](https://github.com/RafaelScharf/SwarmDeck/issues/3) — Multi-tier pipeline with 250ms debounce, carriage return isolation (`\r`), ANSI stripping, OSC 133 semantic prompts, and regex matching inside an actor.
- [Prototype: Sidebar & Multi-Session Architecture](https://github.com/RafaelScharf/SwarmDeck/issues/4) — Native `@Observable` architecture with `NavigationSplitView` allows multiplexing parallel background sessions with zero UI lag and no memory leaks.

## Active Tickets

- [ ] [Task: Process Lifecycle Supervisor & Configurable Spawning](https://github.com/RafaelScharf/SwarmDeck/issues/5)
- [ ] [Task: System Notifications Service via UNUserNotificationCenter](https://github.com/RafaelScharf/SwarmDeck/issues/6)
- [ ] [Task: Session Multiplexer Sidebar & Navigation UX](https://github.com/RafaelScharf/SwarmDeck/issues/7)
- [ ] [Task: Terminal Surface Shortcuts, Clipboard & Layout Sync](https://github.com/RafaelScharf/SwarmDeck/issues/8)
- [ ] [Task: macOS App Packaging, Entitlements & Release Setup](https://github.com/RafaelScharf/SwarmDeck/issues/9)

## Not yet specified

- **Session State Persistence:** Restoring session tabs, working directories, and command histories across application restarts.
- **Custom Agent Detection Rules:** User-configurable regex patterns and triggers per CLI tool via configuration files.

## Out of scope

- Web-based wrappers or Electron implementations.
- Supporting non-macOS platforms (Windows/Linux) for this initial iteration (focus is on native macOS).
- Writing custom terminal emulators from scratch (must use libghostty).
