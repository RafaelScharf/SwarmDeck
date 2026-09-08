import Foundation

/// Strongly-typed identifier for an agent session.
public struct SessionId: Identifiable, Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    
    public var id: UUID { rawValue }
    public var description: String { rawValue.uuidString }
    
    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
    
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = uuid
    }
}

/// Unique identity, configuration, and metadata for an agent session.
///
/// Decoupled from UI and runtime process execution headers.
public struct SessionMetadata: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public let preset: AgentPreset
    public var workingDirectory: String?
    public var customEnvironment: [String: String]
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        preset: AgentPreset = .standardShell,
        workingDirectory: String? = nil,
        customEnvironment: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.workingDirectory = workingDirectory
        self.customEnvironment = customEnvironment
        self.createdAt = createdAt
    }
}

/// Domain entity representing an agent session and its current lifecycle state.
///
/// Fully decoupled from AppKit, SwiftUI, and low-level POSIX headers.
/// Conforms to Swift 6 strict concurrency requirements (`Sendable`).
public struct Session: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public var name: String
    public let preset: AgentPreset
    public var workingDirectory: String?
    public var customEnvironment: [String: String]
    public private(set) var state: AgentState
    public var processId: Int32?
    public private(set) var exitCode: ProcessExitCode?
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        name: String,
        preset: AgentPreset = .standardShell,
        workingDirectory: String? = nil,
        customEnvironment: [String: String] = [:],
        state: AgentState = .idle,
        processId: Int32? = nil,
        exitCode: ProcessExitCode? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.preset = preset
        self.workingDirectory = workingDirectory
        self.customEnvironment = customEnvironment
        self.state = state
        self.processId = processId
        self.exitCode = exitCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public init(
        metadata: SessionMetadata,
        state: AgentState = .idle,
        processId: Int32? = nil,
        exitCode: ProcessExitCode? = nil,
        updatedAt: Date = Date()
    ) {
        self.init(
            id: metadata.id,
            name: metadata.name,
            preset: metadata.preset,
            workingDirectory: metadata.workingDirectory,
            customEnvironment: metadata.customEnvironment,
            state: state,
            processId: processId,
            exitCode: exitCode,
            createdAt: metadata.createdAt,
            updatedAt: updatedAt
        )
    }
    
    /// Returns the session configuration metadata.
    public var metadata: SessionMetadata {
        SessionMetadata(
            id: id,
            name: name,
            preset: preset,
            workingDirectory: workingDirectory,
            customEnvironment: customEnvironment,
            createdAt: createdAt
        )
    }
    
    /// Transitions the session to a new lifecycle state, validating state invariants.
    ///
    /// Throws `AgentStateTransitionError` if the transition is invalid (e.g. attempting
    /// to transition from a terminal `.exited` state).
    public mutating func transition(to newState: AgentState) throws(AgentStateTransitionError) {
        self.state = try self.state.transition(to: newState)
        if case .exited(let code) = newState {
            self.exitCode = code
        }
        self.updatedAt = Date()
    }
}
