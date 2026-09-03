import Foundation
import SwiftUI
import GhosttyTerminal

@MainActor
class PTYController: ObservableObject {
    @Published var viewState: TerminalViewState?
    
    private var pty: PTY?
    
    init() {}
    
    @MainActor
    func start() async {
        do {
            let pty = try PTY()
            self.pty = pty
            
            let session = InMemoryTerminalSession(
                write: { [weak pty] data in
                    print("Received input from ghostty: \(data.count) bytes")
                    pty?.writeToMaster(data)
                },
                resize: { [weak pty] metrics in
                    pty?.resize(columns: Int(metrics.columns), rows: Int(metrics.rows), widthPixels: Int(metrics.widthPixels), heightPixels: Int(metrics.heightPixels))
                }
            )
            
            let options = TerminalSurfaceOptions(backend: .inMemory(session))
            let state = TerminalViewState()
            state.configuration = options
            
            await pty.setOnData { [weak session] data in
                session?.receive(data)
            }
            
            self.viewState = state
            
            try await pty.spawn(executable: "/bin/zsh", arguments: ["-l"])
            
        } catch {
            print("Failed to initialize PTY: \(error)")
        }
    }
}
