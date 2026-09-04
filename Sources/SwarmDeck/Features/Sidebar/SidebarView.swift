import SwiftUI

public struct SidebarView: View {
    @Bindable var store: SessionStore
    
    public init(store: SessionStore) {
        self.store = store
    }
    
    public var body: some View {
        List(selection: $store.selectedSessionId) {
            ForEach(Array(store.sessions.enumerated()), id: \.element.id) { index, session in
                NavigationLink(value: session.id) {
                    AgentRowView(session: session, index: index)
                }
            }
        }
        .navigationTitle("SwarmDeck")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Built-in Presets") {
                        ForEach(AgentPreset.allStandard) { preset in
                            Button {
                                Task {
                                    await store.addSession(preset: preset)
                                }
                            } label: {
                                Label(preset.name, systemImage: preset.iconName)
                            }
                        }
                    }
                    
                    Section {
                        Button {
                            store.showingNewSessionSheet = true
                        } label: {
                            Label("New Custom Session...", systemImage: "slider.horizontal.3")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Spawn Agent Session (Cmd+N)")
            }
        }
        .alert("Active Agent Working", isPresented: $store.showingCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                store.cancelCloseSession()
            }
            Button("Terminate & Close", role: .destructive) {
                store.confirmCloseSession()
            }
        } message: {
            if let pending = store.sessionPendingClose {
                Text("Session '\(pending.name)' is currently running commands. Terminating it may interrupt active operations. Do you want to terminate and close?")
            } else {
                Text("An active agent is working. Do you want to terminate and close?")
            }
        }
    }
}
