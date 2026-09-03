import SwiftUI
import GhosttyTerminal

struct ContentView: View {
    @StateObject private var ptyController = PTYController()

    var body: some View {
        VStack {
            if let viewState = ptyController.viewState {
                TerminalViewRepresentable(
                    context: viewState,
                    controller: viewState.controller,
                    isSurfaceVisible: true,
                    focusBinding: nil
                )
                .onAppear {
                    viewState.requestFocus()
                }
            } else {
                Text("Initializing...")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
