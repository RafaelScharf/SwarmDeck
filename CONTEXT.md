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
2. **Phase 1: Technical Prototype Spikes (Completed):** Resolved technical questions and validated core assumptions through throwaway spikes (PTY `forkpty` allocation, multi-tier state detection, observation multi-session UI, login shell harvesting, backpressure coalescing, socket IPC). Archived in `temp/prototypes/` (Issues #2, #3, #4, #5, #6, #8, #10, #11, #12).
3. **Phase 2: Clean Architecture MVP & Packaging (Completed):** Integrated baseline production structure in `Sources/SwarmDeck/`, sidebar navigation UX, and macOS app packaging pipeline (Issues #7, #9).
4. **Phase 3: Benchmarks Suite & Production Architecture Implementation (Active Frontier):** Executing reproducible benchmarks and production-hardened components (Issues #33 to #42):
   - **Research & Baselines:** Competitor empirical data (Ghostty, Alacritty, iTerm2, Superset/Electron) and semantic shell protocols (OSC 133/633).
   - **Benchmark Harnesses:** PTY throughput/cycle acceleration (> 65 MB/s), dirty memory footprint scaling (< 60 MB idle, < 6 MB/session up to 20 agents), and frame pacing / typing latency (< 15 ms, 120 FPS ProMotion).
   - **Production Architecture:** Swift 6 Sendable domain core, zero-copy byte stream ingestion with sub-3ms prompt detection, Metal surface integration, and declarative workspace persistence.

