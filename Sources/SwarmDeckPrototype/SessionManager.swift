import Foundation
import SwiftUI
import GhosttyTerminal

@Observable
@MainActor
class Session: Identifiable, Hashable {
    let id: UUID
    let name: String
    var state: AgentState = .idle
    var viewState: TerminalViewState?
    
    private var pty: PTY?
    private var detector = OutputStateDetector()
    
    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
    
    nonisolated static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    func start() async {
        do {
            let pty = try PTY()
            self.pty = pty
            
            let terminalSession = InMemoryTerminalSession(
                write: { [weak pty] data in
                    pty?.writeToMaster(data)
                },
                resize: { [weak pty] metrics in
                    pty?.resize(columns: Int(metrics.columns), rows: Int(metrics.rows), widthPixels: Int(metrics.widthPixels), heightPixels: Int(metrics.heightPixels))
                }
            )
            
            let options = TerminalSurfaceOptions(backend: .inMemory(terminalSession))
            let state = TerminalViewState()
            state.configuration = options
            
            await detector.setOnStateChange { [weak self] newState in
                Task { @MainActor in
                    self?.state = newState
                }
            }
            
            await pty.setOnData { [weak terminalSession, weak detector] data in
                terminalSession?.receive(data)
                Task {
                    await detector?.feed(data: data)
                }
            }
            
            self.viewState = state
            
            // For testing, just spawn zsh
            try await pty.spawn(executable: "/bin/zsh", arguments: ["-l"])
            
        } catch {
            print("Failed to initialize session \\(name): \\(error)")
        }
    }
}

@Observable
@MainActor
class SessionManager {
    var sessions: [Session] = []
    var selectedSessionId: UUID?
    
    func addSession(name: String) async {
        let session = Session(name: name)
        sessions.append(session)
        await session.start()
        
        if selectedSessionId == nil {
            selectedSessionId = session.id
        }
    }
}
