import SwiftUI
import AppKit

public struct NewSessionSheet: View {
    @Bindable var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPresetId: String = AgentPreset.standardShell.id
    @State private var sessionName: String = ""
    @State private var command: String = ""
    @State private var arguments: String = ""
    @State private var workingDirectory: String = ""
    
    public init(store: SessionStore) {
        self.store = store
    }
    
    private var activePreset: AgentPreset {
        AgentPreset.allStandard.first(where: { $0.id == selectedPresetId }) ?? .standardShell
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("Spawn Agent Session")
                    .font(.title2.bold())
                Spacer()
            }
            
            // Preset Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Agent Preset")
                    .font(.subheadline.bold())
                
                Picker("Preset", selection: $selectedPresetId) {
                    ForEach(AgentPreset.allStandard) { preset in
                        Label(preset.name, systemImage: preset.iconName)
                            .tag(preset.id)
                    }
                    Label("Custom Command", systemImage: "slider.horizontal.3")
                        .tag("custom")
                }
                .pickerStyle(.segmented)
                
                if selectedPresetId != "custom" {
                    HStack {
                        Image(systemName: activePreset.iconName)
                            .foregroundColor(.secondary)
                        Text(activePreset.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            
            Divider()
            
            // Session Details Form
            Form {
                TextField("Session Name (optional):", text: $sessionName, prompt: Text("e.g. \(activePreset.name)"))
                
                if selectedPresetId == "custom" {
                    TextField("Command / Executable:", text: $command, prompt: Text("e.g. python3, node, aider"))
                    TextField("Arguments (space separated):", text: $arguments, prompt: Text("e.g. -v --debug"))
                }
                
                HStack {
                    TextField("Working Directory (optional):", text: $workingDirectory, prompt: Text("e.g. /Users/.../project"))
                    Button("Browse...") {
                        selectFolder()
                    }
                }
            }
            
            Divider()
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Spawn Session") {
                    spawnSession()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPresetId == "custom" && command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Directory"
        
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }
    
    private func spawnSession() {
        let cwd = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : workingDirectory
        let customName = sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sessionName
        
        let presetToSpawn: AgentPreset
        if selectedPresetId == "custom" {
            let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
            let args = arguments.split(separator: " ").map(String.init)
            presetToSpawn = AgentPreset.custom(
                name: customName ?? cmd,
                command: cmd,
                arguments: args,
                workingDirectory: cwd
            )
        } else {
            presetToSpawn = activePreset
        }
        
        dismiss()
        Task {
            await store.addSession(
                preset: presetToSpawn,
                customName: customName,
                workingDirectory: cwd
            )
        }
    }
}
