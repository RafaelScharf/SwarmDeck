import Foundation

/// Represents a configurable agent or shell preset for PTY execution.
public struct AgentPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var command: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var environment: [String: String]
    public var iconName: String
    public var presetType: PresetType
    
    public enum PresetType: String, Sendable, CaseIterable {
        case standardShell = "shell"
        case claudeCode = "claude"
        case aider = "aider"
        case antigravity = "agy"
        case custom = "custom"
    }
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        iconName: String = "terminal",
        presetType: PresetType = .custom
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.iconName = iconName
        self.presetType = presetType
    }
    
    /// Standard interactive login Zsh shell.
    public static let standardShell = AgentPreset(
        id: "standard-shell",
        name: "Standard Shell",
        command: "/bin/zsh",
        arguments: ["-l"],
        iconName: "apple.terminal",
        presetType: .standardShell
    )
    
    /// Anthropic's Claude Code CLI.
    public static let claudeCode = AgentPreset(
        id: "claude-code",
        name: "Claude Code",
        command: "claude",
        arguments: [],
        iconName: "brain.head.profile",
        presetType: .claudeCode
    )
    
    /// Aider AI pair programming CLI.
    public static let aider = AgentPreset(
        id: "aider",
        name: "Aider",
        command: "aider",
        arguments: [],
        iconName: "sparkles",
        presetType: .aider
    )
    
    /// Google Antigravity CLI (agy).
    public static let antigravity = AgentPreset(
        id: "antigravity",
        name: "Antigravity",
        command: "agy",
        arguments: [],
        iconName: "bolt.horizontal",
        presetType: .antigravity
    )
    
    /// User-defined custom command.
    public static func custom(
        name: String = "Custom Agent",
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) -> AgentPreset {
        AgentPreset(
            id: UUID().uuidString,
            name: name,
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            iconName: "command",
            presetType: .custom
        )
    }
    
    /// Default list of presets available for spawning.
    public static var defaultPresets: [AgentPreset] {
        [.standardShell, .claudeCode, .aider, .antigravity]
    }
}
