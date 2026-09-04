import SwiftUI

public struct AgentRowView: View {
    @Bindable var session: AgentSession
    let index: Int
    @State private var showingRenameAlert: Bool = false
    @State private var renameText: String = ""
    
    public init(session: AgentSession, index: Int) {
        self.session = session
        self.index = index
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // Status badge indicator
            ZStack {
                Circle()
                    .fill(colorForState(session.state))
                    .frame(width: 10, height: 10)
                
                if session.state == .working {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.5)
                }
            }
            
            // Preset icon
            Image(systemName: session.preset.iconName)
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            // Session title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    stateSubtitle(session.state)
                    
                    if let cwd = session.workingDirectory, !cwd.isEmpty {
                        Text("• \(URL(fileURLWithPath: cwd).lastPathComponent)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help(cwd)
                    }
                }
            }
            
            Spacer()
            
            // Keyboard shortcut badge for index 1..9
            if index >= 0 && index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                renameText = session.name
                showingRenameAlert = true
            } label: {
                Label("Rename Session...", systemImage: "pencil")
            }
            
            Button {
                Task {
                    await SessionStore.shared.restartSession(id: session.id)
                }
            } label: {
                Label("Restart Process", systemImage: "arrow.clockwise")
            }
            
            Divider()
            
            if case .exited = session.state {
                Button(role: .destructive) {
                    Task {
                        await SessionStore.shared.closeSession(id: session.id)
                    }
                } label: {
                    Label("Close Session", systemImage: "xmark")
                }
            } else {
                Button {
                    Task {
                        await SessionStore.shared.terminateSession(id: session.id)
                    }
                } label: {
                    Label("Terminate Process", systemImage: "stop.circle")
                }
                
                Button(role: .destructive) {
                    if session.state == .working {
                        SessionStore.shared.sessionPendingClose = session
                        SessionStore.shared.showingCloseConfirmation = true
                    } else {
                        Task {
                            await SessionStore.shared.closeSession(id: session.id)
                        }
                    }
                } label: {
                    Label("Close Session", systemImage: "trash")
                }
            }
        }
        .alert("Rename Session", isPresented: $showingRenameAlert) {
            TextField("Session Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                SessionStore.shared.renameSession(id: session.id, newName: renameText)
            }
        } message: {
            Text("Enter a new display name for this session.")
        }
    }
    
    @ViewBuilder
    private func stateSubtitle(_ state: AgentState) -> some View {
        switch state {
        case .working:
            Text("Working")
                .font(.caption2)
                .foregroundColor(.green)
        case .idle:
            if let pid = session.pid {
                Text("PID: \(pid)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Idle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .blocked(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundColor(.red)
                .help("Waiting for confirmation: \(reason)")
        case .exited(let code):
            Text("Exited (\(code))")
                .font(.caption2)
                .foregroundColor(code == 0 ? .secondary : .red)
        }
    }
    
    private func colorForState(_ state: AgentState) -> Color {
        switch state {
        case .idle: return .gray
        case .working: return .green
        case .blocked: return .red
        case .exited(let code): return code == 0 ? .secondary : .orange
        }
    }
}
