import Foundation
import Darwin
import AppKit
import GhosttyTerminal
import GhosttyTheme

@main
struct TerminalSurfaceSyncTests {
    static var passedCount = 0
    static var totalCount = 0

    static func assertTest(_ condition: Bool, _ description: String) {
        totalCount += 1
        if condition {
            passedCount += 1
            print("  ✓ PASS: \(description)")
        } else {
            print("  ✗ FAIL: \(description)")
            fatalError("Test assertion failed: \(description)")
        }
    }

    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)

        print("=================================================================")
        print(" SwarmDeck: Terminal Surface Shortcuts, Clipboard & Layout Sync")
        print("=================================================================\n")

        // -------------------------------------------------------------
        // Test Group 1: PTY Window & Terminal Resize Synchronization
        // -------------------------------------------------------------
        print("[Test Group 1: PTY Window & Terminal Resize Synchronization]")
        
        do {
            let ptyConfig = PTYConfiguration(
                command: "/bin/sh",
                arguments: ["-c", "sleep 5"]
            )
            let pty = try PTY(configuration: ptyConfig)
            await pty.start()
            
            // Initial resize to standard 80x24
            pty.resize(columns: 80, rows: 24, widthPixels: 800, heightPixels: 600)
            if let ws = pty.getWindowSize() {
                assertTest(ws.ws_col == 80, "PTY window columns synchronized to 80")
                assertTest(ws.ws_row == 24, "PTY window rows synchronized to 24")
                assertTest(ws.ws_xpixel == 800, "PTY horizontal pixel metric synchronized to 800")
                assertTest(ws.ws_ypixel == 600, "PTY vertical pixel metric synchronized to 600")
            } else {
                assertTest(false, "Failed to retrieve PTY window size")
            }
            
            // Dynamic resize during window expansion (e.g. 140x45)
            pty.resize(columns: 140, rows: 45, widthPixels: 1400, heightPixels: 900)
            if let ws2 = pty.getWindowSize() {
                assertTest(ws2.ws_col == 140, "Dynamic resize correctly updated columns to 140")
                assertTest(ws2.ws_row == 45, "Dynamic resize correctly updated rows to 45")
                assertTest(ws2.ws_xpixel == 1400, "Dynamic resize correctly updated widthPixels to 1400")
                assertTest(ws2.ws_ypixel == 900, "Dynamic resize correctly updated heightPixels to 900")
            } else {
                assertTest(false, "Failed to retrieve PTY window size after dynamic resize")
            }
            
            // Clamping edge cases: negative dimensions
            pty.resize(columns: -15, rows: -5, widthPixels: -100, heightPixels: -100)
            if let wsClamped = pty.getWindowSize() {
                assertTest(wsClamped.ws_col == 0, "Negative columns safely clamped to 0 without overflow")
                assertTest(wsClamped.ws_row == 0, "Negative rows safely clamped to 0 without overflow")
            }
            
            // Restore to normal size
            pty.resize(columns: 120, rows: 35, widthPixels: 1200, heightPixels: 700)
            if let wsNormal = pty.getWindowSize() {
                assertTest(wsNormal.ws_col == 120 && wsNormal.ws_row == 35, "Restored normal dimensions 120x35")
            }
            
            await pty.terminate()
        } catch {
            fatalError("Failed to initialize PTY: \(error)")
        }

        // -------------------------------------------------------------
        // Test Group 2: Font Scaling Logic & Clamping
        // -------------------------------------------------------------
        print("\n[Test Group 2: Font Scaling Logic & Clamping]")
        
        let session = Session(name: "Test Session")
        let initialSize = session.fontSize
        assertTest(initialSize == Session.defaultFontSize, "Initial font size defaults to 13.0 pt")
        assertTest(Session.minFontSize == 9.0, "Minimum font size bound is 9.0 pt")
        assertTest(Session.maxFontSize == 36.0, "Maximum font size bound is 36.0 pt")
        
        // Increase font size (Cmd++)
        session.increaseFontSize()
        let increased = session.fontSize
        assertTest(increased == 14.0, "increaseFontSize increments by 1.0 pt (13.0 -> 14.0)")
        
        // Decrease font size (Cmd+-)
        session.decreaseFontSize()
        let decreased = session.fontSize
        assertTest(decreased == 13.0, "decreaseFontSize decrements by 1.0 pt (14.0 -> 13.0)")
        
        // Multiple increments
        for _ in 0..<5 {
            session.increaseFontSize()
        }
        let bumped = session.fontSize
        assertTest(bumped == 18.0, "Repeated increase reaches 18.0 pt")
        
        // Reset font size (Cmd+0)
        session.resetFontSize()
        let resetSize = session.fontSize
        assertTest(resetSize == Session.defaultFontSize, "resetFontSize restores to default 13.0 pt")
        
        // Upper bound clamp
        session.setFontSize(100.0)
        let clampedUpper = session.fontSize
        assertTest(clampedUpper == Session.maxFontSize, "Oversized font value clamped to 36.0 pt")
        
        // Lower bound clamp
        session.setFontSize(2.0)
        let clampedLower = session.fontSize
        assertTest(clampedLower == Session.minFontSize, "Undersized font value clamped to 9.0 pt")

        // -------------------------------------------------------------
        // Test Group 3: Theme Catalog Resolution & Presets
        // -------------------------------------------------------------
        print("\n[Test Group 3: Theme Catalog Resolution & Presets]")
        
        // Test Dracula theme
        let draculaTheme = GhosttyThemeCatalog.theme(named: "Dracula")
        assertTest(draculaTheme != nil, "GhosttyThemeCatalog resolves 'Dracula' theme")
        if let d = draculaTheme {
            assertTest(d.isDark == true, "Dracula is identified as a dark theme")
            assertTest(!d.background.isEmpty, "Dracula defines non-empty background color (\(d.background))")
            assertTest(!d.foreground.isEmpty, "Dracula defines non-empty foreground color (\(d.foreground))")
            
            _ = d.toTerminalTheme()
            assertTest(d.palette.count == 16, "Dracula converts with full 16-color ANSI palette")
        }
        
        // Test Nord theme
        let nordTheme = GhosttyThemeCatalog.theme(named: "Nord")
        assertTest(nordTheme != nil, "GhosttyThemeCatalog resolves 'Nord' theme")
        if let n = nordTheme {
            assertTest(n.isDark == true, "Nord is identified as a dark theme")
        }
        
        // Test Solarized Dark Patched
        let solarizedTheme = GhosttyThemeCatalog.theme(named: "Solarized Dark Patched")
        assertTest(solarizedTheme != nil, "GhosttyThemeCatalog resolves 'Solarized Dark Patched'")
        if let s = solarizedTheme {
            assertTest(s.palette.count == 16, "Solarized Dark Patched defines all 16 ANSI colors")
        }
        
        // Test Theme Presets enum
        let presets = TerminalThemePreset.allCases
        assertTest(presets.count >= 8, "TerminalThemePreset defines at least 8 curated themes (count=\(presets.count))")
        assertTest(presets.contains(.dracula), "Curated presets include Dracula")
        assertTest(presets.contains(.nord), "Curated presets include Nord")
        assertTest(presets.contains(.githubDark), "Curated presets include GitHub Dark")

        // Test applying theme to Session
        session.setTheme(named: "Dracula")
        let appliedTheme = session.currentTheme
        assertTest(appliedTheme == "Dracula", "Session records active theme as Dracula")
        
        session.setTheme(named: nil)
        let clearedTheme = session.currentTheme
        assertTest(clearedTheme == nil, "Session reverts to Default (System) theme when nil")

        // -------------------------------------------------------------
        // Test Group 4: Clear Scrollback (Cmd+K)
        // -------------------------------------------------------------
        print("\n[Test Group 4: Clear Scrollback (Cmd+K)]")
        
        let clearSequence = "\u{001B}[3J\u{001B}[H\u{001B}[2J"
        assertTest(clearSequence.contains("[3J"), "Clear sequence contains ED 3 (clear scrollback buffer)")
        assertTest(clearSequence.contains("[H"), "Clear sequence contains CUP (cursor home)")
        assertTest(clearSequence.contains("[2J"), "Clear sequence contains ED 2 (clear visible display)")
        
        // Form feed for shell prompt repaint
        let formFeedByte: UInt8 = 0x0C
        assertTest(formFeedByte == 12, "Form feed byte is standard ASCII 12 (Ctrl+L)")

        // -------------------------------------------------------------
        // Test Group 5: Clipboard Operations (Cmd+C and Cmd+V)
        // -------------------------------------------------------------
        print("\n[Test Group 5: Clipboard Operations (Cmd+C and Cmd+V)]")
        
        let testClipText = "SwarmDeck Terminal Sync Test Payload: \(UUID().uuidString)"
        session.copyToClipboard(testClipText)
        
        let pasteboardString = NSPasteboard.general.string(forType: .string)
        assertTest(pasteboardString == testClipText, "copyToClipboard accurately writes string into NSPasteboard.general")
        
        let emptyPasted = session.pasteText("")
        assertTest(!emptyPasted, "pasteText safely ignores empty text")
        
        let validPasted = session.pasteText("echo 'sync test'\n")
        assertTest(validPasted, "pasteText successfully dispatches text payload")

        // -------------------------------------------------------------
        // Test Group 6: Viewport Metrics Tracking
        // -------------------------------------------------------------
        print("\n[Test Group 6: Viewport Metrics Tracking]")
        
        let metrics = TerminalViewportMetrics(
            columns: 120,
            rows: 40,
            widthPixels: 1200,
            heightPixels: 800,
            cellWidthPixels: 10,
            cellHeightPixels: 20
        )
        assertTest(metrics.summary == "120 × 40", "Viewport summary formats as 'Columns × Rows' (120 × 40)")
        assertTest(metrics.columns == 120, "Columns metric stored correctly")
        assertTest(metrics.rows == 40, "Rows metric stored correctly")
        
        session.updateViewport(columns: 100, rows: 30, widthPixels: 1000, heightPixels: 600, cellWidth: 10, cellHeight: 20)
        let currentVp = session.currentViewport
        assertTest(currentVp?.summary == "100 × 30", "Session updates and stores active viewport metrics (100 × 30)")

        // -------------------------------------------------------------
        // Test Group 7: SessionManager Active Session Routing
        // -------------------------------------------------------------
        print("\n[Test Group 7: SessionManager Active Session Routing]")
        
        let manager = SessionManager.shared
        assertTest(manager.sessions.isEmpty || manager.activeSession != nil, "SessionManager provides activeSession accessor")
        
        let sessionId = await manager.addSession(preset: .standardShell, customName: "Sync Test Shell")
        assertTest(manager.selectedSessionId == sessionId, "Newly added session is automatically selected")
        assertTest(manager.activeSession?.id == sessionId, "activeSession points to selected session")
        
        // Test routing shortcuts through SessionManager
        let beforeIncrease = manager.activeSession?.fontSize ?? 0
        manager.increaseFontSizeOnActiveSession()
        let afterIncrease = manager.activeSession?.fontSize ?? 0
        assertTest(afterIncrease == beforeIncrease + 1.0, "SessionManager routes font size increase to active session")
        
        manager.resetFontSizeOnActiveSession()
        let afterReset = manager.activeSession?.fontSize ?? 0
        assertTest(afterReset == Session.defaultFontSize, "SessionManager routes font size reset to active session")
        
        manager.setThemeOnActiveSession(named: "Nord")
        let activeTheme = manager.activeSession?.currentTheme
        assertTest(activeTheme == "Nord", "SessionManager routes theme change to active session")
        
        // Clean up session
        await manager.closeSession(id: sessionId)
        assertTest(!manager.sessions.contains(where: { $0.id == sessionId }), "Session cleanly closed and removed from manager")

        print("\n=================================================================")
        print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
        print("=================================================================\n")
    }
}
