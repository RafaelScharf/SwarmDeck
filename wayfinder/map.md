# Wayfinder Map: SwarmDeck

## Destination

A native macOS SwiftUI application embedding `libghostty` to multiplex and manage background PTY processes for AI coding agents, providing sidebar navigation and system notifications for agent state changes.

## Notes

- **Domain:** macOS native development (SwiftUI), Terminal emulation, Process Management (PTY).
- **Core Tech:** Swift 6 Concurrency, libghostty-spm (Zig/Metal), UserNotifications.
- **Goal:** Zero WebView overhead, minimal latency, robust background execution.
- All core technical spikes (#2, #3, #4) have completed. Current phase is executing the implementation roadmap.

## Architecture Blueprint (Minimum Viable Architecture)

The production codebase (`Sources/SwarmDeck/`) follows a clean, decoupled, layered architecture adhering to modern Swift 6 Concurrency (`actor` for thread-safe POSIX/IO isolation and `@Observable` for SwiftUI presentation), with zero third-party framework dependencies:

```text
Sources/SwarmDeck/
├── App/
│   ├── SwarmDeckApp.swift              // @main entry point, window lifecycle
│   └── AppDelegate.swift               // UNUserNotificationCenter delegate, deep-link handling
├── Domain/                             // Pure domain models & value types (Zero UI/POSIX dependencies)
│   ├── Session.swift                   // Session identity, metadata, working directory, timestamps
│   ├── AgentPreset.swift               // Presets: Standard Shell, Claude Code, Aider, Antigravity, Custom
│   └── AgentState.swift                // Lifecycle states: .idle, .working, .blocked(reason), .exited(code)
├── Services/                           // Low-level & asynchronous engines (Actors / Sendable)
│   ├── PTY/
│   │   ├── PTYService.swift            // forkpty, TIOCSCTTY, async-signal safe execve, window resizing
│   │   └── ProcessSupervisor.swift     // DispatchSourceProcess, automatic waitpid zombie reaping, SIGTERM/SIGKILL
│   ├── Detection/
│   │   └── AgentStateDetector.swift    // VT100/ANSI stream parser, 250ms debounce, regex prompt heuristics
│   └── Notification/
│       └── NotificationService.swift   // UNUserNotificationCenter, debounce rate-limiting, deep-link payload
└── Features/                           // Presentation layer (SwiftUI + @Observable)
    ├── SessionStore.swift              // Central @Observable state orchestrator
    ├── Sidebar/
    │   ├── SidebarView.swift           // NavigationSplitView sidebar, session list, badges
    │   └── AgentRowView.swift          // Row item, contextual menus (Terminate, Close, Restart)
    ├── Terminal/
    │   ├── TerminalContainerView.swift // Session header bar, status indicators, surface host
    │   └── TerminalSurfaceView.swift   // NSViewRepresentable wrapping libghostty Metal surface
    └── Spawning/
        └── CustomAgentSheet.swift      // Modal for custom agent command, args, and working directory
```

## Decisions so far

- [Prototype: Minimal SwiftUI PTY App](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/prototype-minimal-swiftui-pty-resolution.md) ([#2](https://github.com/RafaelScharf/SwarmDeck/issues/2)) — Embedded `libghostty-spm` via `InMemoryTerminalSession` and switched to `forkpty()` inside a Swift Actor for controlling terminal (`TIOCSCTTY`), job control, and signal handling. Spike scripts organized in [`temp/prototypes/`](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/temp/prototypes/).
- [Prototype: Agent State Detection Engine](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/prototype-agent-state-detection-resolution.md) ([#3](https://github.com/RafaelScharf/SwarmDeck/issues/3)) — Multi-tier pipeline with 250ms debounce, carriage return isolation (`\r`), ANSI stripping, OSC 133 semantic prompts, and regex matching inside an actor. Test harness organized in [`temp/prototypes/prototype_state_detector.swift`](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/temp/prototypes/prototype_state_detector.swift).
- [Prototype: Sidebar & Multi-Session Architecture](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/prototype-sidebar-multisession-resolution.md) ([#4](https://github.com/RafaelScharf/SwarmDeck/issues/4)) — Native `@Observable` architecture with `NavigationSplitView` allows multiplexing parallel background sessions with zero UI lag and no memory leaks.
- [Prototype: Process Lifecycle Supervisor & Configurable Spawning](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/task-process-lifecycle-supervisor-resolution.md) ([#5](https://github.com/RafaelScharf/SwarmDeck/issues/5)) — `DispatchSourceProcess` monitoring `.exit` with immediate `waitpid` reaps child processes to prevent zombies, decodes POSIX exit statuses, escalates `SIGTERM` to `SIGKILL` gracefully, and supports `AgentPreset` models with custom working directories and enriched environment inheritance.

## Active Tickets

### Phase 1: Technical Prototype Spikes (`temp/prototypes/`)
- [x] [Prototype: Minimal SwiftUI PTY App](https://github.com/RafaelScharf/SwarmDeck/issues/2)
- [x] [Prototype: Agent State Detection Engine](https://github.com/RafaelScharf/SwarmDeck/issues/3)
- [x] [Prototype: Sidebar & Multi-Session Architecture](https://github.com/RafaelScharf/SwarmDeck/issues/4)
- [x] [Prototype: Process Lifecycle Supervisor & Configurable Spawning](https://github.com/RafaelScharf/SwarmDeck/issues/5)
- [ ] [Prototype: System Notifications via UNUserNotificationCenter](https://github.com/RafaelScharf/SwarmDeck/issues/6)
- [ ] [Prototype: Terminal Surface Shortcuts, Clipboard & Layout Sync](https://github.com/RafaelScharf/SwarmDeck/issues/8)
- [ ] [Prototype: macOS Login Shell Environment Harvesting](https://github.com/RafaelScharf/SwarmDeck/issues/10)
- [ ] [Prototype: PTY High-Throughput Backpressure & Stream Coalescing](https://github.com/RafaelScharf/SwarmDeck/issues/11)
- [ ] [Prototype: Unix Domain Socket IPC & CLI Dispatcher](https://github.com/RafaelScharf/SwarmDeck/issues/12)

### Phase 2: Clean Architecture MVP Implementation (Autonomous PR Loop)
- [ ] [Task: Session Multiplexer Sidebar & Navigation UX](https://github.com/RafaelScharf/SwarmDeck/issues/7)
- [ ] [Task: macOS App Packaging, Entitlements & Release Setup](https://github.com/RafaelScharf/SwarmDeck/issues/9)

## Not yet specified

- **Session State Persistence Strategy:** Declarative workspace topology and buffer snapshot (`~/.config/swarmdeck/workspace.json`) adopted for Phase 2; out-of-process `tmux`-style daemon formally rejected for MVP.
- **Custom Agent Detection Rules:** User-configurable regex patterns and triggers per CLI tool via JSON configuration files.

## Out of scope

- Web-based wrappers or Electron implementations.
- Supporting non-macOS platforms (Windows/Linux) for this initial iteration (focus is on native macOS).
- Writing custom terminal emulators from scratch (must use libghostty).
