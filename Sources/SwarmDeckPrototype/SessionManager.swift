import Foundation
import SwiftUI
import GhosttyTerminal

@Observable
@MainActor
class Session: Identifiable, Hashable {
    let id: UUID
    let name: String
    let preset: AgentPreset
    let workingDirectory: String?
    let customEnvironment: [String: String]
    
    var state: AgentState = .idle
    var viewState: TerminalViewState?
    var pid: pid_t?
    var exitCode: Int32?
    weak var manager: SessionManager?
    
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
                resize: { [weak pty] metrics in
                    pty?.resize(
                        columns: Int(metrics.columns),
                        rows: Int(metrics.rows),
                        widthPixels: Int(metrics.widthPixels),
                        heightPixels: Int(metrics.heightPixels)
                    )
                }
            )
            
            let options = TerminalSurfaceOptions(backend: .inMemory(terminalSession))
            let state = TerminalViewState()
            state.configuration = options
            
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
            
            self.viewState = state
            
            // Start PTY reading and process supervision
            await pty.start()
            
        } catch {
            print("Failed to initialize session \(name): \(error.localizedDescription)")
            self.state = .exited(code: -1)
        }
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
}
