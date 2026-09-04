import Foundation

/// Unique identity and metadata for an agent session.
public struct SessionMetadata: Identifiable, Sendable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public let preset: AgentPreset
    public var workingDirectory: String?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        preset: AgentPreset,
        workingDirectory: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
    }
}
