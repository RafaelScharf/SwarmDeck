import Foundation
import SwiftUI
import GhosttyTerminal

class PTYController: ObservableObject {
    @Published var viewState: TerminalViewState?
    
    private var pty: PTY?
    
    init() {
        start()
    }
    
    func start() {
        do {
            let pty = try PTY()
            self.pty = pty
            
            let session = InMemoryTerminalSession(
                write: { [weak pty] data in
                    pty?.writeToMaster(data)
                },
                resize: { [weak pty] metrics in
                    pty?.resize(columns: metrics.columns, rows: metrics.rows, widthPixels: metrics.widthPixels, heightPixels: metrics.heightPixels)
                }
            )
            
            let options = TerminalSurfaceOptions(backend: .inMemory(session))
            let state = TerminalViewState()
            state.configuration = options
            
            pty.onData = { [weak session] data in
                session?.receive(data)
            }
            
            self.viewState = state
            
            try pty.spawn(executable: "/bin/zsh", arguments: ["-l"])
            
        } catch {
            print("Failed to initialize PTY: \(error)")
        }
    }
}
