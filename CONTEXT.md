# SwarmDeck - Project Context & Architecture

## Overview
SwarmDeck is a high-performance GUI and terminal multiplexer specifically tailored for managing multiple AI coding agent sessions (e.g., Claude Code, Aider, Antigravity).

## Core Requirements
- **Sidebar Navigation:** Visual list of active agent sessions.
- **Terminal View:** Render the terminal output of the selected session.
- **Background Execution:** Agents must continue running in the background when not focused.
- **Visual Notifications:** Status indicators (badges/dots) in the sidebar and system notifications when an agent requires human input (e.g., blocked, waiting for approval).

## Tech Stack Decision
To achieve the goal of being the **fastest and most robust** tool in its category, avoiding the memory penalties and rendering lag of Electron or web-based wrappers (like Superset or Claude Code GUI):

**Chosen Stack: Native Swift + libghostty**
- **UI Layer:** Native Swift (SwiftUI). Provides flawless OS integration, a native `NavigationSplitView` for the sidebar, and `UNUserNotificationCenter` for visual/system notifications. Zero WebView overhead.
- **Terminal Engine:** `libghostty` (Zig/Metal). Offers industry-leading, GPU-accelerated terminal rendering. By integrating ghostty's surface directly into SwiftUI, SwarmDeck will have virtually zero latency.
- **Process Management:** Swift Concurrency (`actor`-based `AgentSessionManager`). Handles background PTY (pseudo-terminal) processes, monitoring output streams for regex triggers to detect when an agent needs input.

### Why not Rust/Tauri or Go/Wails?
While Rust + Tauri with `xterm.js` is great, it relies on a web view. The DOM/Canvas rendering overhead prevents it from being the absolute fastest. Swift + libghostty guarantees native memory efficiency and bleeding-edge rendering speeds on macOS.

## Development Strategy (Matt Pocock Flow)
1. **Wayfinder:** Establish project boundaries, core data models (Session, PTY, Status).
2. **Grilling & Prototypes (Completed):** Resolved technical questions and validated core assumptions through throwaway spikes (PTY `forkpty` allocation, multi-tier state detection, observation multi-session UI). Archived in `temp/prototypes/` (Issues #2, #3, #4).
3. **Implementation Frontier:** Executing modular implementation tasks charted in `wayfinder/map.md` (Process supervisor, notifications, sidebar UX, terminal polish, app release).
