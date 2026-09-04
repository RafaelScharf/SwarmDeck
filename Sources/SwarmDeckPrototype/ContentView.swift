import SwiftUI
import GhosttyTerminal

struct ContentView: View {
    @State private var sessionManager = SessionManager()
    @FocusState private var isFocused: Bool
    @State private var showingCustomPresetSheet = false
    
    // Custom agent configuration form state
    @State private var customCommand = ""
    @State private var customArguments = ""
    @State private var customWorkingDirectory = ""
    @State private var customName = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $sessionManager.selectedSessionId) {
                ForEach(sessionManager.sessions) { session in
                    NavigationLink(value: session.id) {
                        HStack(spacing: 8) {
                            // Status indicator badge
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
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                HStack(spacing: 6) {
                                    switch session.state {
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
                                        Text("Blocked: \(reason)")
                                            .font(.caption2)
                                            .foregroundColor(.red)
                                    case .exited(let code):
                                        Text("Exited (\(code))")
                                            .font(.caption2)
                                            .foregroundColor(code == 0 ? .secondary : .red)
                                    }
                                    
                                    if let cwd = session.workingDirectory, !cwd.isEmpty {
                                        Text("• \(URL(fileURLWithPath: cwd).lastPathComponent)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            if case .exited = session.state {
                                Button(role: .destructive) {
                                    Task {
                                        await sessionManager.closeSession(id: session.id)
                                    }
                                } label: {
                                    Label("Close Session", systemImage: "xmark")
                                }
                            } else {
                                Button {
                                    Task {
                                        await sessionManager.terminateSession(id: session.id)
                                    }
                                } label: {
                                    Label("Terminate Process", systemImage: "stop.circle")
                                }
                                
                                Button(role: .destructive) {
                                    Task {
                                        await sessionManager.closeSession(id: session.id)
                                    }
                                } label: {
                                    Label("Close & Kill Session", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("SwarmDeck")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Built-in Presets") {
                            Button {
                                Task {
                                    await sessionManager.addSession(preset: .standardShell)
                                }
                            } label: {
                                Label("Standard Shell (/bin/zsh)", systemImage: "apple.terminal")
                            }
                            
                            Button {
                                Task {
                                    await sessionManager.addSession(preset: .claudeCode)
                                }
                            } label: {
                                Label("Claude Code (claude)", systemImage: "brain.head.profile")
                            }
                            
                            Button {
                                Task {
                                    await sessionManager.addSession(preset: .aider)
                                }
                            } label: {
                                Label("Aider (aider)", systemImage: "sparkles")
                            }
                            
                            Button {
                                Task {
                                    await sessionManager.addSession(preset: .antigravity)
                                }
                            } label: {
                                Label("Antigravity (agy)", systemImage: "bolt.horizontal")
                            }
                        }
                        
                        Section {
                            Button {
                                showingCustomPresetSheet = true
                            } label: {
                                Label("Custom Command...", systemImage: "slider.horizontal.3")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let sessionId = sessionManager.selectedSessionId,
               let session = sessionManager.sessions.first(where: { $0.id == sessionId }) {
                VStack(spacing: 0) {
                    // Header Bar
                    HStack {
                        Image(systemName: session.preset.iconName)
                            .foregroundColor(.secondary)
                        
                        Text(session.name)
                            .font(.headline)
                        
                        if let pid = session.pid {
                            Text("(PID: \(pid))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        switch session.state {
                        case .working:
                            HStack(spacing: 4) {
                                ProgressView().controlSize(.small).scaleEffect(0.6)
                                Text("Working").font(.caption).foregroundColor(.green)
                            }
                        case .idle:
                            Text("Idle").font(.caption).foregroundColor(.secondary)
                        case .blocked(let reason):
                            Text("Blocked: \(reason)").font(.caption).foregroundColor(.red)
                        case .exited(let code):
                            HStack(spacing: 6) {
                                Text("Exited with code \(code)")
                                    .font(.caption)
                                    .foregroundColor(code == 0 ? .secondary : .red)
                            }
                        }
                        
                        if case .exited = session.state {
                            Button("Close") {
                                Task {
                                    await sessionManager.closeSession(id: session.id)
                                }
                            }
                            .controlSize(.small)
                        } else {
                            Button("Terminate") {
                                Task {
                                    await sessionManager.terminateSession(id: session.id)
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    if let viewState = session.viewState {
                        TerminalSurfaceView(context: viewState)
                            .terminalFocused($isFocused)
                            .onAppear {
                                isFocused = true
                                viewState.requestFocus()
                            }
                            .id(sessionId)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Launching process...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Agent Session Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Select an existing session from the sidebar or click '+' to spawn a new agent.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .sheet(isPresented: $showingCustomPresetSheet) {
            VStack(spacing: 16) {
                Text("Spawn Custom Agent")
                    .font(.title3.bold())
                
                Form {
                    TextField("Session Name (optional):", text: $customName, prompt: Text("e.g. Code Reviewer"))
                    TextField("Command / Binary:", text: $customCommand, prompt: Text("e.g. python3, git, claude"))
                    TextField("Arguments (space separated):", text: $customArguments, prompt: Text("e.g. -v --debug"))
                    TextField("Working Directory (optional):", text: $customWorkingDirectory, prompt: Text("e.g. /Users/.../project"))
                }
                .padding(.horizontal)
                
                HStack {
                    Button("Cancel") {
                        showingCustomPresetSheet = false
                    }
                    Spacer()
                    Button("Spawn Agent") {
                        let cmd = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cmd.isEmpty else { return }
                        let args = customArguments.split(separator: " ").map(String.init)
                        let cwd = customWorkingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customWorkingDirectory
                        let preset = AgentPreset.custom(
                            name: customName.isEmpty ? cmd : customName,
                            command: cmd,
                            arguments: args,
                            workingDirectory: cwd
                        )
                        showingCustomPresetSheet = false
                        Task {
                            await sessionManager.addSession(
                                preset: preset,
                                customName: customName.isEmpty ? nil : customName,
                                workingDirectory: cwd
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(customCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
            }
            .padding(24)
            .frame(width: 450)
        }
        .task {
            if sessionManager.sessions.isEmpty {
                // Initialize default agent sessions
                await sessionManager.addSession(preset: .standardShell, customName: "Shell (Zsh)")
                await sessionManager.addSession(preset: .claudeCode, customName: "Agent (Claude)")
                await sessionManager.addSession(preset: .antigravity, customName: "Agent (Antigravity)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSessionNotification)) { notification in
            if let sessionId = notification.userInfo?["sessionId"] as? UUID {
                sessionManager.selectedSessionId = sessionId
            }
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
