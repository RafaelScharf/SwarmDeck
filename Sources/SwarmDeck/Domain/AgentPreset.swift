import Foundation

/// Defines a pre-configured or custom agent environment and execution parameters.
public struct AgentPreset: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let description: String
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]
    public let iconName: String
    
    public init(
        id: String,
        name: String,
        description: String,
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        iconName: String = "terminal"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.iconName = iconName
    }
    
    // MARK: - Standard Presets
    
    public static let standardShell = AgentPreset(
        id: "shell",
        name: "Standard Shell",
        description: "Interactive macOS default login shell (/bin/zsh)",
        command: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        arguments: ["-l"],
        iconName: "apple.terminal"
    )
    
    public static let claudeCode = AgentPreset(
        id: "claude",
        name: "Claude Code",
        description: "Anthropic's autonomous coding CLI agent",
        command: "claude",
        arguments: [],
        iconName: "brain.head.profile"
    )
    
    public static let aider = AgentPreset(
        id: "aider",
        name: "Aider",
        description: "AI pair programming in the terminal",
        command: "aider",
        arguments: [],
        iconName: "sparkles"
    )
    
    public static let antigravity = AgentPreset(
        id: "antigravity",
        name: "Antigravity",
        description: "Google Advanced Agentic Coding CLI (agy)",
        command: "agy",
        arguments: [],
        iconName: "bolt.horizontal"
    )
    
    public static func custom(
        name: String,
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) -> AgentPreset {
        AgentPreset(
            id: "custom-\(UUID().uuidString.prefix(8))",
            name: name,
            description: "Custom executable: \(command)",
            command: command,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            iconName: "slider.horizontal.3"
        )
    }
    
    public static let allStandard: [AgentPreset] = [
        .standardShell,
        .claudeCode,
        .aider,
        .antigravity
    ]
}
