---
type: prototype-resolution
ticket: issue-8
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/8
branch: feat/issue-8-terminal-surface-sync
---

# Resolution: Prototype - Terminal Surface Shortcuts, Clipboard & Layout Sync

## Question
How do we provide native macOS terminal ergonomics (clipboard, clear scrollback, font sizing, responsive layout) within libghostty's Metal surface?

## Findings & Implementation

1. **PTY Window and Terminal Resize Synchronization:**
   - Enhanced `PTY.resize(columns:rows:widthPixels:heightPixels:)` to clamp metrics safely (`UInt16(clamping: max(0, ...))`), protecting against negative or overflow dimensions during window drag.
   - Added thread-safe `lastWinSize` tracking (`OSAllocatedUnfairLock<winsize?>`) to avoid redundant `ioctl(TIOCSWINSZ)` system calls and spurious `SIGWINCH` signals when window coordinates don't change the underlying grid.
   - Implemented `PTY.getWindowSize() -> winsize?` for non-blocking inspection and validation.
   - Enabled `suppressesPixelOnlyResizes: true` on `InMemoryTerminalSession` to prevent excessive redraw storms during sidebar dragging, while immediately notifying the PTY whenever character column/row counts change.
   - Captured real-time viewport metrics (`TerminalViewportMetrics`) on `@MainActor` and exposed a terminal dimension indicator (e.g. `120 × 40`) directly in the header bar.

2. **Dynamic Font Scaling:**
   - Implemented reactive font scaling on `Session` with bounds clamping: default 13.0 pt, minimum 9.0 pt, maximum 36.0 pt, and 1.0 pt step increments.
   - Supported standard macOS shortcuts: `Cmd++` / `Cmd+=` (Increase), `Cmd+-` (Decrease), and `Cmd+0` (Reset to default 13.0 pt).
   - Applied updates dynamically via `viewState.setTerminalConfiguration(TerminalConfiguration { $0.withFontSize(Float(fontSize)) })`.
   - Exposed interactive zoom steppers and reset button in the session header bar.

3. **Curated Themes & Catalog Resolution:**
   - Linked `GhosttyTheme` library product and integrated `GhosttyThemeCatalog`.
   - Defined `TerminalThemePreset` enum supporting curated themes: `Default (System)`, `Dracula`, `Nord`, `GitHub Dark`, `Monokai Pro`, `One Dark Two`, `TokyoNight`, and `Solarized Dark`.
   - Implemented `Session.setTheme(named:)` dynamically applying `toTerminalTheme()` and `toTerminalConfiguration()`, updating both the Metal surface colors and custom font sizing without restarting the session.
   - Added a theme selector menu in the header bar and macOS app menu.

4. **Terminal Actions: Clear Scrollback (Cmd+K):**
   - Implemented `Session.clearScrollback()`:
     1. Dispatches standard VT escape sequences `\u{001B}[3J\u{001B}[H\u{001B}[2J` (`ED 3` + `CUP` + `ED 2`) to `InMemoryTerminalSession.receive` to clear Ghostty's scrollback buffer and wipe the visible viewport.
     2. Dispatches ASCII 12 (`0x0C` / Form Feed / Ctrl+L) to `pty.writeToMaster` to trigger line-editor prompt repainting at line 1.
   - Bound to `Cmd+K` keyboard shortcut, header bar "Clear" button, and Terminal application menu.

5. **Clipboard Operations (Cmd+C and Cmd+V):**
   - Validated Ghostty's native `copy_to_clipboard` and `paste_from_clipboard` bindings in `AppTerminalView`.
   - Implemented explicit fallback and programmatic clipboard helpers on `Session`:
     - `pasteFromClipboard()` reads string from `NSPasteboard.general` and writes to the terminal via `viewState.paste(text:)` (which applies bracketed paste framing) or fallback to `pty.writeToMaster`.
     - `copySelectionOrViewport()` extracts visible text via `InMemoryTerminalSession.readViewportText()` and writes to `NSPasteboard.general`.
   - Added quick "Paste" button in the header bar and IPC RPC methods (`clear`, `paste`, `fontSize`, `theme`).

## Test Validation
- Created comprehensive 53-point automated validation test suite in `temp/prototypes/test_terminal_surface_sync.swift`.
- Validated:
  1. PTY window column, row, and pixel dimension synchronization through Darwin `ioctl(TIOCSWINSZ)` and `ioctl(TIOCGWINSZ)`.
  2. Safe clamping against negative dimensions.
  3. Font scaling increments, decrements, reset, and upper/lower bound clamping (9.0 pt .. 36.0 pt).
  4. Theme resolution for Dracula, Nord, and Solarized Dark Patched with complete 16-color ANSI palettes.
  5. Clear scrollback escape sequence structure and Ctrl+L Form Feed byte.
  6. Clipboard write (`copyToClipboard`) and read (`pasteText`) interactions with `NSPasteboard.general`.
  7. Real-time `TerminalViewportMetrics` tracking and session header summary formatting.
  8. `SessionManager` active session accessor and global shortcut routing.
- All 53 tests passed with 100% success rate.
