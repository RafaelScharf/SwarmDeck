import SwiftUI
import GhosttyTerminal

struct ContentView: View {
    @StateObject private var ptyController = PTYController()
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            if let viewState = ptyController.viewState {
                TerminalSurfaceView(context: viewState)
                    .terminalFocused($isFocused)
                    .onAppear {
                        isFocused = true
                        viewState.requestFocus()
                    }
            } else {
                Text("Initializing...")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            if ptyController.viewState == nil {
                await ptyController.start()
            }
        }
    }
}
