# Wayfinder Map: SwarmDeck

## Destination

A native macOS SwiftUI application embedding `libghostty` to multiplex and manage background PTY processes for AI coding agents, providing sidebar navigation and system notifications for agent state changes.

## Notes

- **Domain:** macOS native development (SwiftUI), Terminal emulation, Process Management (PTY).
- **Core Tech:** Swift, libghostty (Zig/Metal).
- **Goal:** Zero WebView overhead, minimal latency, robust background execution.
- Use `research` subagents to investigate external C/Zig APIs and Swift bridging.

## Decisions so far

- [Agent Output State Detection](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/agent-output-state-detection-resolution.md) — Must use a multi-tier pipeline (debounce, OSC 133, ANSI stripping, targeted regex) via Swift Actor.
- [Swift PTY Management](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/swift-pty-management-resolution.md) — Use `openpty()`, `DispatchSourceRead` with `AsyncStream`, and strict slave FD cleanup inside an actor to avoid macOS crashes.
- [libghostty Swift Integration](file:///Users/rafaelkscharf/Projects/homelab/SwarmDeck/wayfinder/tickets/libghostty-swift-integration-resolution.md) — Use `GhosttyKit.xcframework` C-ABI directly in Swift via `NSViewRepresentable`, initializing on the main thread and letting Ghostty's Metal layer handle rendering without custom draw loops.

## Not yet specified

*(All known fog has graduated to active Prototype tickets #2, #3, and #4)*

## Out of scope

- Web-based wrappers or Electron implementations.
- Supporting non-macOS platforms (Windows/Linux) for this initial iteration (focus is on native macOS).
- Writing custom terminal emulators from scratch (must use libghostty).
