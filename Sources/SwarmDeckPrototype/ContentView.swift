import SwiftUI
import GhosttyTerminal

struct ContentView: View {
    @State private var sessionManager = SessionManager()
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(selection: $sessionManager.selectedSessionId) {
                ForEach(sessionManager.sessions) { session in
                    NavigationLink(value: session.id) {
                        HStack {
                            Circle()
                                .fill(colorForState(session.state))
                                .frame(width: 10, height: 10)
                            
                            if session.state == .working {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.6)
                            }
                            
                            Text(session.name)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await sessionManager.addSession(name: "Session \\(sessionManager.sessions.count + 1)")
                        }
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let sessionId = sessionManager.selectedSessionId,
               let session = sessionManager.sessions.first(where: { $0.id == sessionId }),
               let viewState = session.viewState {
                TerminalSurfaceView(context: viewState)
                    .terminalFocused($isFocused)
                    .onAppear {
                        isFocused = true
                        viewState.requestFocus()
                    }
                    .id(sessionId) // Force re-render when switching to ensure Ghostty surface is attached
            } else {
                Text("Select a session")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            if sessionManager.sessions.isEmpty {
                await sessionManager.addSession(name: "Agent 1 (Aider)")
                await sessionManager.addSession(name: "Agent 2 (Claude)")
                await sessionManager.addSession(name: "Agent 3 (Fast)")
            }
        }
    }
    
    private func colorForState(_ state: AgentState) -> Color {
        switch state {
        case .idle: return .gray
        case .working: return .green
        case .blocked: return .red
        case .exited: return .black
        }
    }
}
