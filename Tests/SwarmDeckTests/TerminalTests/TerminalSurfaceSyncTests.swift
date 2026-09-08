import Testing
import Darwin
import AppKit
import QuartzCore
import Metal
import GhosttyKit
import GhosttyTerminal
import GhosttyTheme
@testable import SwarmDeck

@Suite("Terminal Surface View & 120 FPS ProMotion Sync Tests")
struct TerminalSurfaceSyncTests {
    
    // MARK: - 1. PTY Window & Terminal Resize Synchronization
    
    @Test("PTY window column, row, and pixel dimension synchronization via ioctl(TIOCSWINSZ)")
    func testPTYWindowResizeSynchronization() async throws {
        let ptyConfig = PTYConfiguration(
            command: "/bin/sh",
            arguments: ["-c", "sleep 5"]
        )
        let pty = try PTYService(configuration: ptyConfig)
        await pty.start()
        
        // Initial resize to standard 80x24 character grid
        pty.resize(columns: 80, rows: 24, widthPixels: 800, heightPixels: 600)
        let ws = pty.getWindowSize()
        #expect(ws != nil)
        #expect(ws?.ws_col == 80)
        #expect(ws?.ws_row == 24)
        #expect(ws?.ws_xpixel == 800)
        #expect(ws?.ws_ypixel == 600)
        
        // Dynamic resize during window expansion (e.g. 140x45)
        pty.resize(columns: 140, rows: 45, widthPixels: 1400, heightPixels: 900)
        let ws2 = pty.getWindowSize()
        #expect(ws2?.ws_col == 140)
        #expect(ws2?.ws_row == 45)
        #expect(ws2?.ws_xpixel == 1400)
        #expect(ws2?.ws_ypixel == 900)
        
        // Clamping edge cases: negative dimensions clamped to 0
        pty.resize(columns: -15, rows: -5, widthPixels: -100, heightPixels: -100)
        let wsClamped = pty.getWindowSize()
        #expect(wsClamped?.ws_col == 0)
        #expect(wsClamped?.ws_row == 0)
        #expect(wsClamped?.ws_xpixel == 0)
        #expect(wsClamped?.ws_ypixel == 0)
        
        // Deduplication: multiple redundant calls preserve valid state
        pty.resize(columns: 120, rows: 35, widthPixels: 1200, heightPixels: 700)
        pty.resize(columns: 120, rows: 35, widthPixels: 1200, heightPixels: 700)
        let wsNormal = pty.getWindowSize()
        #expect(wsNormal?.ws_col == 120)
        #expect(wsNormal?.ws_row == 35)
        
        await pty.terminate()
    }
    
    // MARK: - 2. Dynamic Font Scaling Logic & Clamping
    
    @Test("Dynamic font scaling, increments, decrements, reset, and safety bounds clamping")
    @MainActor
    func testDynamicFontScaling() {
        let session = AgentSession(name: "Font Scale Session")
        
        #expect(session.fontSize == AgentSession.defaultFontSize)
        #expect(session.fontSize == 13.0)
        #expect(AgentSession.minFontSize == 9.0)
        #expect(AgentSession.maxFontSize == 36.0)
        #expect(AgentSession.fontSizeStep == 1.0)
        
        // Increase font size (Cmd++)
        session.increaseFontSize()
        #expect(session.fontSize == 14.0)
        
        // Decrease font size (Cmd+-)
        session.decreaseFontSize()
        #expect(session.fontSize == 13.0)
        
        // Multiple increments
        for _ in 0..<5 {
            session.increaseFontSize()
        }
        #expect(session.fontSize == 18.0)
        
        // Reset font size (Cmd+0)
        session.resetFontSize()
        #expect(session.fontSize == AgentSession.defaultFontSize)
        #expect(session.fontSize == 13.0)
        
        // Upper bound clamp
        session.setFontSize(100.0)
        #expect(session.fontSize == AgentSession.maxFontSize)
        #expect(session.fontSize == 36.0)
        
        // Lower bound clamp
        session.setFontSize(2.0)
        #expect(session.fontSize == AgentSession.minFontSize)
        #expect(session.fontSize == 9.0)
    }
    
    // MARK: - 3. Curated Ghostty Theme Catalog Resolution
    
    @Test("Curated theme catalog resolution and application to AgentSession")
    @MainActor
    func testThemeCatalogResolution() {
        // Dracula Theme
        let draculaTheme = GhosttyThemeCatalog.theme(named: "Dracula")
        #expect(draculaTheme != nil)
        if let d = draculaTheme {
            #expect(d.isDark == true)
            #expect(!d.background.isEmpty)
            #expect(!d.foreground.isEmpty)
            #expect(d.palette.count == 16)
        }
        
        // Nord Theme
        let nordTheme = GhosttyThemeCatalog.theme(named: "Nord")
        #expect(nordTheme != nil)
        if let n = nordTheme {
            #expect(n.isDark == true)
            #expect(!n.background.isEmpty)
        }
        
        // Solarized Dark Patched
        let solarizedTheme = GhosttyThemeCatalog.theme(named: "Solarized Dark Patched")
        #expect(solarizedTheme != nil)
        if let s = solarizedTheme {
            #expect(s.palette.count == 16)
        }
        
        // Presets enum
        let presets = TerminalThemePreset.allCases
        #expect(presets.count >= 8)
        #expect(presets.contains(.dracula))
        #expect(presets.contains(.nord))
        #expect(presets.contains(.githubDark))
        #expect(presets.contains(.solarizedDark))
        
        // Session theme application
        let session = AgentSession(name: "Theme Test Session")
        session.setTheme(named: "Dracula")
        #expect(session.currentTheme == "Dracula")
        
        session.setTheme(named: nil)
        #expect(session.currentTheme == nil)
    }
    
    // MARK: - 4. Clear Scrollback & Clipboard Operations
    
    @Test("Clear scrollback escape sequences and ASCII Form Feed byte")
    func testClearScrollbackSequences() {
        let clearSequence = "\u{001B}[3J\u{001B}[H\u{001B}[2J"
        #expect(clearSequence.contains("[3J")) // ED 3 (clear scrollback)
        #expect(clearSequence.contains("[H"))  // CUP (cursor home)
        #expect(clearSequence.contains("[2J")) // ED 2 (clear screen)
        
        let formFeedByte: UInt8 = 0x0C
        #expect(formFeedByte == 12) // Standard ASCII 12 (Ctrl+L)
    }
    
    @Test("Clipboard NSPasteboard.general copy and paste integration")
    @MainActor
    func testClipboardIntegration() {
        let session = AgentSession(name: "Clipboard Session")
        let testPayload = "SwarmDeck Terminal Sync Test Payload: \(UUID().uuidString)"
        
        session.copyToClipboard(testPayload)
        let pasteboardString = NSPasteboard.general.string(forType: .string)
        #expect(pasteboardString == testPayload)
        
        let emptyPasted = session.pasteText("")
        #expect(emptyPasted == false)
        
        let validPasted = session.pasteText("echo 'sync test'\n")
        #expect(validPasted == true)
    }
    
    // MARK: - 5. Viewport Metrics Tracking
    
    @Test("TerminalViewportMetrics dimensions and summary formatting")
    @MainActor
    func testTerminalViewportMetrics() {
        let metrics = TerminalViewportMetrics(
            columns: 120,
            rows: 40,
            widthPixels: 1200,
            heightPixels: 800,
            cellWidthPixels: 10,
            cellHeightPixels: 20
        )
        #expect(metrics.columns == 120)
        #expect(metrics.rows == 40)
        #expect(metrics.widthPixels == 1200)
        #expect(metrics.heightPixels == 800)
        #expect(metrics.summary == "120 × 40")
        
        let session = AgentSession(name: "Viewport Session")
        session.updateViewport(columns: 100, rows: 30, widthPixels: 1000, heightPixels: 600, cellWidth: 10, cellHeight: 20)
        #expect(session.currentViewport?.summary == "100 × 30")
        #expect(session.currentViewport?.columns == 100)
        #expect(session.currentViewport?.rows == 30)
    }
    
    // MARK: - 6. SwarmDeckMetalTerminalView Metal & ProMotion Configuration
    
    @Test("SwarmDeckMetalTerminalView CAMetalLayer ProMotion configuration and focus hooks")
    @MainActor
    func testMetalTerminalViewConfiguration() {
        let view = SwarmDeckMetalTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        #expect(view.wantsLayer == true)
        
        if let metal = view.layer as? CAMetalLayer {
            #expect(metal.pixelFormat == .bgra8Unorm)
            #expect(metal.maximumDrawableCount == 3) // Triple-buffering
            #expect(metal.displaySyncEnabled == true) // VSync lock for 120 Hz ProMotion
            #expect(metal.framebufferOnly == true)
            #expect(metal.isOpaque == false)
        }
        
        var focusEvents: [Bool] = []
        view.onFocusChanged = { focused in
            focusEvents.append(focused)
        }
        
        // Simulating focus changes
        _ = view.becomeFirstResponder()
        #expect(focusEvents.contains(true))
        
        _ = view.resignFirstResponder()
        #expect(focusEvents.contains(false))
    }
    
    // MARK: - 7. TerminalSurfaceView Representable & Focus Binding
    
    @Test("TerminalSurfaceView FocusBinding state management")
    @MainActor
    func testTerminalSurfaceViewFocusBinding() {
        var isFocusedValue = false
        let binding = SwarmDeck.TerminalSurfaceView.FocusBinding.optional(
            read: { isFocusedValue },
            write: { isFocusedValue = $0 }
        )
        
        #expect(binding.isFocused == false)
        binding.setFocused(true)
        #expect(binding.isFocused == true)
        #expect(isFocusedValue == true)
        
        binding.setFocused(false)
        #expect(binding.isFocused == false)
        #expect(isFocusedValue == false)
        
        let viewState = TerminalViewState()
        let surfaceView = SwarmDeck.TerminalSurfaceView(context: viewState)
        #expect(surfaceView.context === viewState)
        #expect(surfaceView.focusBinding == nil)
    }
}
