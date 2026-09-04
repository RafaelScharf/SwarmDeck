import SwiftUI
import GhosttyTerminal

public struct MainView: View {
    @State private var store = SessionStore.shared
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            if let sessionId = store.selectedSessionId,
               let session = store.sessions.first(where: { $0.id == sessionId }) {
                TerminalContainerView(session: session)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 56))
                        .foregroundColor(.secondary)
                    
                    Text("No Agent Session Selected")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    
                    Text("Select an existing session from the sidebar or click '+' to spawn a new agent.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    Button {
                        store.showingNewSessionSheet = true
                    } label: {
                        Label("Spawn New Agent", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 960, minHeight: 680)
        .sheet(isPresented: $store.showingNewSessionSheet) {
            NewSessionSheet(store: store)
        }
        .task {
            if store.sessions.isEmpty {
                await store.addSession(preset: .standardShell, customName: "Shell (Zsh)")
                await store.addSession(preset: .claudeCode, customName: "Agent (Claude)")
                await store.addSession(preset: .antigravity, customName: "Agent (Antigravity)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSessionNotification)) { notification in
            if let sessionId = notification.userInfo?["sessionId"] as? UUID {
                store.selectedSessionId = sessionId
            }
        }
        .background {
            // Invisible background buttons providing reliable keyboard navigation
            Group {
                // Number shortcuts Cmd+1 through Cmd+9
                Button("") { store.selectSession(at: 0) }.keyboardShortcut("1", modifiers: .command)
                Button("") { store.selectSession(at: 1) }.keyboardShortcut("2", modifiers: .command)
                Button("") { store.selectSession(at: 2) }.keyboardShortcut("3", modifiers: .command)
                Button("") { store.selectSession(at: 3) }.keyboardShortcut("4", modifiers: .command)
                Button("") { store.selectSession(at: 4) }.keyboardShortcut("5", modifiers: .command)
                Button("") { store.selectSession(at: 5) }.keyboardShortcut("6", modifiers: .command)
                Button("") { store.selectSession(at: 6) }.keyboardShortcut("7", modifiers: .command)
                Button("") { store.selectSession(at: 7) }.keyboardShortcut("8", modifiers: .command)
                Button("") { store.selectSession(at: 8) }.keyboardShortcut("9", modifiers: .command)
                
                // Spawn new session: Cmd+N and Cmd+T
                Button("") { store.showingNewSessionSheet = true }.keyboardShortcut("n", modifiers: .command)
                Button("") { store.showingNewSessionSheet = true }.keyboardShortcut("t", modifiers: .command)
                
                // Close active session: Cmd+W
                Button("") { store.requestCloseActiveSession() }.keyboardShortcut("w", modifiers: .command)
                
                // Terminal Actions
                Button("") { store.clearScrollbackOnActiveSession() }.keyboardShortcut("k", modifiers: .command)
                Button("") { store.increaseFontSizeOnActiveSession() }.keyboardShortcut("+", modifiers: .command)
                Button("") { store.increaseFontSizeOnActiveSession() }.keyboardShortcut("=", modifiers: .command)
                Button("") { store.decreaseFontSizeOnActiveSession() }.keyboardShortcut("-", modifiers: .command)
                Button("") { store.resetFontSizeOnActiveSession() }.keyboardShortcut("0", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
    }
}
