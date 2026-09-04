import Foundation
import SwiftUI
import GhosttyTerminal
import GhosttyTheme

/// Terminal viewport metrics representing the active character grid and pixel dimensions.
public struct TerminalViewportMetrics: Sendable, Equatable {
    public let columns: Int
    public let rows: Int
    public let widthPixels: Int
    public let heightPixels: Int
    public let cellWidthPixels: Int
    public let cellHeightPixels: Int
    
    public init(
        columns: Int = 80,
        rows: Int = 24,
        widthPixels: Int = 0,
        heightPixels: Int = 0,
        cellWidthPixels: Int = 0,
        cellHeightPixels: Int = 0
    ) {
        self.columns = columns
        self.rows = rows
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.cellWidthPixels = cellWidthPixels
        self.cellHeightPixels = cellHeightPixels
    }
    
    public var summary: String {
        "\(columns) × \(rows)"
    }
}

/// Popular built-in theme presets supported by libghostty theme catalog.
public enum TerminalThemePreset: String, CaseIterable, Identifiable, Sendable {
    case system = "Default"
    case dracula = "Dracula"
    case nord = "Nord"
    case githubDark = "GitHub Dark"
    case monokaiPro = "Monokai Pro"
    case oneDarkTwo = "One Dark Two"
    case tokyoNight = "TokyoNight"
    case solarizedDark = "Solarized Dark"
    
    public var id: String { rawValue }
    
    public var themeName: String? {
        switch self {
        case .system: return nil
        case .dracula: return "Dracula"
        case .nord: return "Nord"
        case .githubDark: return "GitHub Dark"
        case .monokaiPro: return "Monokai Pro"
        case .oneDarkTwo: return "One Dark Two"
        case .tokyoNight: return "TokyoNight"
        case .solarizedDark: return "Solarized Dark Patched"
        }
    }
}

@Observable
@MainActor
class Session: Identifiable, Hashable {
    let id: UUID
    let name: String
    let preset: AgentPreset
    let workingDirectory: String?
    let customEnvironment: [String: String]
    
    // Font Scaling constants and state
    public static let defaultFontSize: Double = 13.0
    public static let minFontSize: Double = 9.0
    public static let maxFontSize: Double = 36.0
    public static let fontSizeStep: Double = 1.0

    var fontSize: Double = Session.defaultFontSize
    var currentTheme: String? = nil
    var currentViewport: TerminalViewportMetrics? = nil

    var state: AgentState = .idle
    var viewState: TerminalViewState?
    var pid: pid_t?
    var exitCode: Int32?
    weak var manager: SessionManager?
    
    private(set) var terminalSession: InMemoryTerminalSession?
    private var pty: PTY?
    private var detector = OutputStateDetector()
    private var coalescer: PTYStreamCoalescer?
    
    init(
        id: UUID = UUID(),
        name: String,
        preset: AgentPreset = .standardShell,
        workingDirectory: String? = nil,
        customEnvironment: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.workingDirectory = workingDirectory
        self.customEnvironment = customEnvironment
    }
    
    nonisolated static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    func start() async {
        do {
            let config = PTYConfiguration(
                command: preset.command,
                arguments: preset.arguments,
                workingDirectory: workingDirectory,
                environment: customEnvironment
            )
            let pty = try PTY(configuration: config)
            self.pty = pty
            self.pid = pty.childPID
            
            let terminalSession = InMemoryTerminalSession(
                write: { [weak pty] data in
                    pty?.writeToMaster(data)
                },
                resize: { [weak self, weak pty] metrics in
                    pty?.resize(
                        columns: Int(metrics.columns),
                        rows: Int(metrics.rows),
                        widthPixels: Int(metrics.widthPixels),
                        heightPixels: Int(metrics.heightPixels)
                    )
                    Task { @MainActor in
                        self?.currentViewport = TerminalViewportMetrics(
                            columns: Int(metrics.columns),
                            rows: Int(metrics.rows),
                            widthPixels: Int(metrics.widthPixels),
                            heightPixels: Int(metrics.heightPixels),
                            cellWidthPixels: Int(metrics.cellWidthPixels),
                            cellHeightPixels: Int(metrics.cellHeightPixels)
                        )
                    }
                },
                suppressesPixelOnlyResizes: true
            )
            self.terminalSession = terminalSession
            
            let options = TerminalSurfaceOptions(backend: .inMemory(terminalSession))
            let state = TerminalViewState()
            state.configuration = options
            self.viewState = state
            applyConfiguration()
            
            await detector.setOnStateChange { [weak self] newState in
                Task { @MainActor in
                    guard let self = self else { return }
                    // Only apply detector states if process hasn't exited
                    if case .exited = self.state {
                        return
                    }
                    self.state = newState
                    let isAppActive = NSApplication.shared.isActive
                    let isSelected = (self.manager?.selectedSessionId == self.id)
                    let sessionId = self.id
                    let sessionName = self.name
                    Task {
                        await NotificationService.shared.handleStateChange(
                            sessionId: sessionId,
                            sessionName: sessionName,
                            newState: newState,
                            isSessionActive: isSelected,
                            isAppActive: isAppActive
                        )
                    }
                }
            }
            
            let coalescer = PTYStreamCoalescer(
                onBatch: { [weak terminalSession, weak detector] batch in
                    terminalSession?.receive(batch)
                    await detector?.feed(data: batch)
                }
            )
            self.coalescer = coalescer
            
            await pty.setOnData { [weak coalescer] data in
                coalescer?.yield(data)
            }
            
            await pty.setOnExit { [weak self, weak coalescer] exitCode in
                coalescer?.finish()
                Task { @MainActor in
                    guard let self = self else { return }
                    let newState = AgentState.exited(code: exitCode)
                    self.state = newState
                    self.exitCode = exitCode
                    let isAppActive = NSApplication.shared.isActive
                    let isSelected = (self.manager?.selectedSessionId == self.id)
                    let sessionId = self.id
                    let sessionName = self.name
                    Task {
                        await NotificationService.shared.handleStateChange(
                            sessionId: sessionId,
                            sessionName: sessionName,
                            newState: newState,
                            isSessionActive: isSelected,
                            isAppActive: isAppActive
                        )
                    }
                }
            }
            
            // Start PTY reading and process supervision
            await pty.start()
            
        } catch {
            print("Failed to initialize session \(name): \(error.localizedDescription)")
            self.state = .exited(code: -1)
        }
    }
    
    // MARK: - Font Scaling
    
    func increaseFontSize() {
        setFontSize(fontSize + Session.fontSizeStep)
    }
    
    func decreaseFontSize() {
        setFontSize(fontSize - Session.fontSizeStep)
    }
    
    func resetFontSize() {
        setFontSize(Session.defaultFontSize)
    }
    
    func setFontSize(_ size: Double) {
        let clamped = max(Session.minFontSize, min(Session.maxFontSize, size))
        guard clamped != fontSize else { return }
        fontSize = clamped
        applyConfiguration()
    }
    
    // MARK: - Theme Management
    
    func setTheme(named name: String?) {
        self.currentTheme = name
        if let name = name, let themeDef = GhosttyThemeCatalog.theme(named: name) {
            _ = viewState?.setTheme(themeDef.toTerminalTheme())
        }
        applyConfiguration()
    }
    
    // MARK: - Configuration Application
    
    func applyConfiguration() {
        let currentSize = Float(fontSize)
        let themeName = currentTheme
        let themeDef = themeName.flatMap { GhosttyThemeCatalog.theme(named: $0) }
        
        let config = TerminalConfiguration { builder in
            builder.withFontSize(currentSize)
            if let themeDef {
                builder.withBackground(themeDef.background)
                builder.withForeground(themeDef.foreground)
                if let cursorColor = themeDef.cursorColor {
                    builder.withCursorColor(cursorColor)
                }
                if let cursorText = themeDef.cursorText {
                    builder.withCursorText(cursorText)
                }
                if let selBg = themeDef.selectionBackground {
                    builder.withSelectionBackground(selBg)
                }
                if let selFg = themeDef.selectionForeground {
                    builder.withSelectionForeground(selFg)
                }
                for index in themeDef.palette.keys.sorted() {
                    if let color = themeDef.palette[index] {
                        builder.withPalette(index, color: "#\(color)")
                    }
                }
            }
        }
        _ = viewState?.setTerminalConfiguration(config)
    }
    
    // MARK: - Terminal Shortcuts & Actions
    
    /// Clears the terminal scrollback buffer and resets visible screen (Cmd+K).
    func clearScrollback() {
        // 1. Send ED 3 (clear scrollback) + CUP (cursor home) + ED 2 (clear display) to Ghostty display
        let clearSequence = "\u{001B}[3J\u{001B}[H\u{001B}[2J"
        terminalSession?.receive(clearSequence)
        
        // 2. Send Form Feed (Ctrl+L) to child process stdin to trigger prompt repaint
        pty?.writeToMaster(Data([0x0C]))
    }
    
    // MARK: - Clipboard Operations
    
    /// Pastes given string into the terminal surface or PTY.
    @discardableResult
    func pasteText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if let viewState = self.viewState, viewState.paste(text: text) {
            return true
        }
        pty?.writeToMaster(Data(text.utf8))
        return true
    }
    
    /// Pastes text from the system clipboard (Cmd+V).
    @discardableResult
    func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return false
        }
        return pasteText(text)
    }
    
    /// Reads viewport text or copies to clipboard (Cmd+C helper).
    @discardableResult
    func copySelectionOrViewport() -> String? {
        if let text = terminalSession?.readViewportText(), !text.isEmpty {
            copyToClipboard(text)
            return text
        }
        return nil
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Viewport Synchronization
    
    func updateViewport(columns: Int, rows: Int, widthPixels: Int, heightPixels: Int, cellWidth: Int = 0, cellHeight: Int = 0) {
        self.currentViewport = TerminalViewportMetrics(
            columns: columns,
            rows: rows,
            widthPixels: widthPixels,
            heightPixels: heightPixels,
            cellWidthPixels: cellWidth,
            cellHeightPixels: cellHeight
        )
    }
    
    func terminate() async {
        coalescer?.cancel()
        await pty?.terminate()
    }
}

@Observable
@MainActor
class SessionManager {
    static let shared = SessionManager()
    
    var sessions: [Session] = []
    var selectedSessionId: UUID?
    
    var activeSession: Session? {
        guard let id = selectedSessionId else { return sessions.first }
        return sessions.first(where: { $0.id == id })
    }
    
    /// Spawns and adds a new session with configurable agent preset, cwd, and environment.
    @discardableResult
    func addSession(
        preset: AgentPreset = .standardShell,
        customName: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) async -> UUID {
        let countForPreset = sessions.filter { $0.preset.id == preset.id }.count + 1
        let name = customName ?? "\(preset.name) \(countForPreset)"
        
        let session = Session(
            name: name,
            preset: preset,
            workingDirectory: workingDirectory,
            customEnvironment: environment
        )
        session.manager = self
        sessions.append(session)
        await session.start()
        
        if selectedSessionId == nil {
            selectedSessionId = session.id
        }
        return session.id
    }
    
    /// Legacy compatibility helper.
    func addSession(name: String) async {
        await addSession(preset: .standardShell, customName: name)
    }
    
    /// Terminates the child process and removes the session from the manager.
    func closeSession(id: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        await session.terminate()
        sessions.remove(at: index)
        
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
        }
    }
    
    /// Terminates the child process but keeps the terminal surface open to review history.
    func terminateSession(id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        await session.terminate()
    }
    
    func clearScrollbackOnActiveSession() {
        activeSession?.clearScrollback()
    }
    
    func increaseFontSizeOnActiveSession() {
        activeSession?.increaseFontSize()
    }
    
    func decreaseFontSizeOnActiveSession() {
        activeSession?.decreaseFontSize()
    }
    
    func resetFontSizeOnActiveSession() {
        activeSession?.resetFontSize()
    }
    
    func pasteOnActiveSession() {
        activeSession?.pasteFromClipboard()
    }
    
    func setThemeOnActiveSession(named: String?) {
        activeSession?.setTheme(named: named)
    }
}
