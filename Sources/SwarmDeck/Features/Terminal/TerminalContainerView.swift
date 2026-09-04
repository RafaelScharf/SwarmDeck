import SwiftUI
import GhosttyTerminal

public struct TerminalContainerView: View {
    @Bindable var session: AgentSession
    @FocusState private var isTerminalFocused: Bool
    
    public init(session: AgentSession) {
        self.session = session
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: session.preset.iconName)
                        .foregroundColor(.secondary)
                    
                    Text(session.name)
                        .font(.headline)
                    
                    if let pid = session.pid {
                        Text("(PID: \(pid))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Terminal Dimensions Badge
                if let vp = session.currentViewport {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.2x2")
                            .font(.caption2)
                        Text(vp.summary)
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
                    .help("Terminal Dimensions (Columns × Rows)")
                }
                
                // Font Size Controls
                HStack(spacing: 2) {
                    Button {
                        session.decreaseFontSize()
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Decrease Font Size (Cmd+-)")
                    
                    Text("\(Int(session.fontSize))pt")
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 28)
                    
                    Button {
                        session.increaseFontSize()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Increase Font Size (Cmd++)")
                    
                    if session.fontSize != AgentSession.defaultFontSize {
                        Button {
                            session.resetFontSize()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help("Reset Font Size to 13pt (Cmd+0)")
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
                
                // Theme Selector
                Menu {
                    Button {
                        session.setTheme(named: nil)
                    } label: {
                        HStack {
                            Text("Default (System)")
                            if session.currentTheme == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Divider()
                    
                    ForEach(TerminalThemePreset.allCases) { preset in
                        if let name = preset.themeName {
                            Button {
                                session.setTheme(named: name)
                            } label: {
                                HStack {
                                    Text(preset.rawValue)
                                    if session.currentTheme == name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                            .font(.caption2)
                        Text(session.currentTheme ?? "Theme")
                            .font(.caption)
                    }
                }
                .menuStyle(.borderlessButton)
                
                Spacer()
                
                // Quick Action buttons: Clear & Paste
                Button {
                    session.clearScrollback()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Clear Terminal Scrollback (Cmd+K)")
                
                Button {
                    session.pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Paste Clipboard (Cmd+V)")
                
                // State Badge
                stateBadge(session.state)
                
                // Terminate / Close button
                if case .exited = session.state {
                    Button("Close") {
                        Task {
                            await session.store?.closeSession(id: session.id)
                        }
                    }
                    .controlSize(.small)
                } else {
                    Button("Terminate") {
                        Task {
                            await session.store?.terminateSession(id: session.id)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Metal Terminal Surface
            if let viewState = session.viewState {
                TerminalSurfaceView(context: viewState)
                    .terminalFocused($isTerminalFocused)
                    .onAppear {
                        isTerminalFocused = true
                        viewState.requestFocus()
                    }
                    .id(session.id)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Launching process...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func stateBadge(_ state: AgentState) -> some View {
        switch state {
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
                Text("Exited (\(code))")
                    .font(.caption)
                    .foregroundColor(code == 0 ? .secondary : .red)
            }
        }
    }
}
