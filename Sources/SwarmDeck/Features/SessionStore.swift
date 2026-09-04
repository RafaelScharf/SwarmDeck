import Foundation
import SwiftUI
import AppKit
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
public final class AgentSession: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public let preset: AgentPreset
    public let workingDirectory: String?
    public let customEnvironment: [String: String]
    public let createdAt: Date
    
    // Font Scaling state
    public static let defaultFontSize: Double = 13.0
    public static let minFontSize: Double = 9.0
    public static let maxFontSize: Double = 36.0
    public static let fontSizeStep: Double = 1.0

    public var fontSize: Double = AgentSession.defaultFontSize
    public var currentTheme: String? = nil
    public var currentViewport: TerminalViewportMetrics? = nil

    public var state: AgentState = .idle
    public var viewState: TerminalViewState?
    public var pid: pid_t?
    public var exitCode: Int32?
    public weak var store: SessionStore?
    
    private(set) public var terminalSession: InMemoryTerminalSession?
    private var pty: PTYService?
    private var detector = AgentStateDetector()
    private var coalescer: PTYStreamCoalescer?
    
    public init(
        id: UUID = UUID(),
        name: String,
        preset: AgentPreset = .standardShell,
        workingDirectory: String? = nil,
        customEnvironment: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.workingDirectory = workingDirectory
        self.customEnvironment = customEnvironment
        self.createdAt = createdAt
    }
    
    public nonisolated static func == (lhs: AgentSession, rhs: AgentSession) -> Bool {
        lhs.id == rhs.id
    }
    
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public func start() async {
        do {
            let config = PTYConfiguration(
                command: preset.command,
                arguments: preset.arguments,
                workingDirectory: workingDirectory,
                environment: customEnvironment
            )
            let pty = try PTYService(configuration: config)
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
                    if case .exited = self.state { return }
                    self.state = newState
                    let isAppActive = NSApplication.shared.isActive
                    let isSelected = (self.store?.selectedSessionId == self.id)
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
                    let isSelected = (self.store?.selectedSessionId == self.id)
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
            
            await pty.start()
            
        } catch {
            print("Failed to initialize session \(name): \(error.localizedDescription)")
            self.state = .exited(code: -1)
        }
    }
    
    // MARK: - Font Scaling
    
    public func increaseFontSize() {
        setFontSize(fontSize + AgentSession.fontSizeStep)
    }
    
    public func decreaseFontSize() {
        setFontSize(fontSize - AgentSession.fontSizeStep)
    }
    
    public func resetFontSize() {
        setFontSize(AgentSession.defaultFontSize)
    }
    
    public func setFontSize(_ size: Double) {
        let clamped = max(AgentSession.minFontSize, min(AgentSession.maxFontSize, size))
        guard clamped != fontSize else { return }
        fontSize = clamped
        applyConfiguration()
    }
    
    // MARK: - Theme Management
    
    public func setTheme(named name: String?) {
        self.currentTheme = name
        if let name = name, let themeDef = GhosttyThemeCatalog.theme(named: name) {
            _ = viewState?.setTheme(themeDef.toTerminalTheme())
        }
        applyConfiguration()
    }
    
    public func applyConfiguration() {
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
    
    public func clearScrollback() {
        let clearSequence = "\u{001B}[3J\u{001B}[H\u{001B}[2J"
        terminalSession?.receive(clearSequence)
        pty?.writeToMaster(Data([0x0C]))
    }
    
    @discardableResult
    public func pasteText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        if let viewState = self.viewState, viewState.paste(text: text) {
            return true
        }
        pty?.writeToMaster(Data(text.utf8))
        return true
    }
    
    @discardableResult
    public func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return false
        }
        return pasteText(text)
    }
    
    @discardableResult
    public func copySelectionOrViewport() -> String? {
        if let text = terminalSession?.readViewportText(), !text.isEmpty {
            copyToClipboard(text)
            return text
        }
        return nil
    }
    
    public func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    public func updateViewport(columns: Int, rows: Int, widthPixels: Int, heightPixels: Int, cellWidth: Int = 0, cellHeight: Int = 0) {
        self.currentViewport = TerminalViewportMetrics(
            columns: columns,
            rows: rows,
            widthPixels: widthPixels,
            heightPixels: heightPixels,
            cellWidthPixels: cellWidth,
            cellHeightPixels: cellHeight
        )
    }
    
    public func terminate() async {
        coalescer?.cancel()
        await pty?.terminate()
    }
}

@Observable
@MainActor
public final class SessionStore {
    public static let shared = SessionStore()
    
    public var sessions: [AgentSession] = []
    public var selectedSessionId: UUID?
    
    // Close confirmation dialog state
    public var sessionPendingClose: AgentSession?
    public var showingCloseConfirmation: Bool = false
    
    // Sheet creation state
    public var showingNewSessionSheet: Bool = false
    
    public var activeSession: AgentSession? {
        guard let id = selectedSessionId else { return sessions.first }
        return sessions.first(where: { $0.id == id })
    }
    
    public init() {}
    
    @discardableResult
    public func addSession(
        preset: AgentPreset = .standardShell,
        customName: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) async -> UUID {
        let countForPreset = sessions.filter { $0.preset.id == preset.id }.count + 1
        let name = customName ?? "\(preset.name) \(countForPreset)"
        
        let session = AgentSession(
            name: name,
            preset: preset,
            workingDirectory: workingDirectory,
            customEnvironment: environment
        )
        session.store = self
        sessions.append(session)
        await session.start()
        
        selectedSessionId = session.id
        return session.id
    }
    
    public func closeSession(id: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        await session.terminate()
        sessions.remove(at: index)
        
        if selectedSessionId == id {
            selectedSessionId = sessions.first?.id
        }
    }
    
    public func terminateSession(id: UUID) async {
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        await session.terminate()
    }
    
    public func restartSession(id: UUID) async {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let oldSession = sessions[index]
        await oldSession.terminate()
        
        let newSession = AgentSession(
            id: oldSession.id,
            name: oldSession.name,
            preset: oldSession.preset,
            workingDirectory: oldSession.workingDirectory,
            customEnvironment: oldSession.customEnvironment
        )
        newSession.store = self
        sessions[index] = newSession
        await newSession.start()
    }
    
    public func renameSession(id: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let session = sessions.first(where: { $0.id == id }) else { return }
        session.name = trimmed
    }
    
    // MARK: - Keyboard Navigation (Cmd+1..Cmd+9, Cmd+W)
    
    public func selectSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }
        selectedSessionId = sessions[index].id
    }
    
    public func requestCloseActiveSession() {
        guard let session = activeSession else { return }
        if session.state == .working {
            sessionPendingClose = session
            showingCloseConfirmation = true
        } else {
            Task {
                await closeSession(id: session.id)
            }
        }
    }
    
    public func confirmCloseSession() {
        guard let session = sessionPendingClose else { return }
        sessionPendingClose = nil
        showingCloseConfirmation = false
        Task {
            await closeSession(id: session.id)
        }
    }
    
    public func cancelCloseSession() {
        sessionPendingClose = nil
        showingCloseConfirmation = false
    }
    
    // MARK: - Actions on Active Session
    
    public func clearScrollbackOnActiveSession() {
        activeSession?.clearScrollback()
    }
    
    public func increaseFontSizeOnActiveSession() {
        activeSession?.increaseFontSize()
    }
    
    public func decreaseFontSizeOnActiveSession() {
        activeSession?.decreaseFontSize()
    }
    
    public func resetFontSizeOnActiveSession() {
        activeSession?.resetFontSize()
    }
    
    public func pasteOnActiveSession() {
        activeSession?.pasteFromClipboard()
    }
    
    public func setThemeOnActiveSession(named: String?) {
        activeSession?.setTheme(named: named)
    }
}
