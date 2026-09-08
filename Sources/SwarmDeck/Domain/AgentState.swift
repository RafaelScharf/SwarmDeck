import Foundation

/// Structured reason describing why an agent is in the `.blocked` state.
public struct BlockedReason: Sendable, Equatable, Hashable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String
    
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral value: String) {
        self.rawValue = value
    }
    
    public var description: String { rawValue }
    
    // MARK: - Well-Known Standard Reasons
    
    /// The agent executed a command or action requiring explicit user confirmation (e.g. `[y/N]`, `approve?`).
    public static let confirmationRequired = BlockedReason("Confirmation Required")
    
    /// The agent triggered a terminal bell alert (`\u{07}` / BEL).
    public static let terminalBell = BlockedReason("Terminal Bell Alert")
    
    /// The agent requires interactive user input or credential entry.
    public static let inputRequired = BlockedReason("User Input Required")
    
    /// The agent encountered a permission prompt or requires elevated permissions.
    public static let permissionRequired = BlockedReason("Permission Required")
}

/// Representation of a process termination exit status code.
public struct ProcessExitCode: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let rawValue: Int32
    
    public init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public var description: String { "\(rawValue)" }
    
    /// Returns `true` if the process terminated successfully (exit code 0).
    public var isSuccess: Bool { rawValue == 0 }
    
    /// Returns `true` if the process terminated due to a fatal Unix signal (> 128).
    public var isSignalTerminated: Bool { rawValue > 128 }
    
    // MARK: - Well-Known Exit Codes
    
    public static let success = ProcessExitCode(0)
    public static let failure = ProcessExitCode(1)
    public static let sigint = ProcessExitCode(130)  // 128 + SIGINT (2)
    public static let sigkill = ProcessExitCode(137) // 128 + SIGKILL (9)
    public static let sigterm = ProcessExitCode(143) // 128 + SIGTERM (15)
}

/// Error thrown when an invalid lifecycle state transition is attempted.
public enum AgentStateTransitionError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidTransition(from: AgentState, to: AgentState)
    
    public var description: String {
        switch self {
        case .invalidTransition(let from, let to):
            return "Invalid AgentState transition from '\(from)' to '\(to)'"
        }
    }
}

/// Formal lifecycle state machine of an AI agent or shell process.
///
/// Invariants:
/// - `.exited` is a terminal state. Once a process has exited, transitions to other states
///   are prohibited; session respawn or reset must initialize a new lifecycle state.
/// - Active states (`.idle`, `.working`, `.blocked`) may transition between each other or into `.exited`.
public enum AgentState: Sendable, Equatable, Hashable, Codable {
    /// Agent or process is idling at the shell or awaiting input.
    case idle
    
    /// Agent is actively processing, running commands, or generating tokens.
    case working
    
    /// Agent is blocked and awaiting user action, confirmation prompt, or input.
    case blocked(reason: BlockedReason)
    
    /// Agent process has terminated with the specified POSIX exit status code.
    case exited(code: ProcessExitCode)
    
    // MARK: - Convenience Initializers / Overloads
    
    public static func blocked(reason: String) -> AgentState {
        .blocked(reason: BlockedReason(reason))
    }
    
    public static func exited(code: Int32) -> AgentState {
        .exited(code: ProcessExitCode(code))
    }
    
    // MARK: - State Inspection Properties
    
    /// Returns `true` if this is a terminal state (`.exited`).
    public var isTerminal: Bool {
        switch self {
        case .exited: return true
        default: return false
        }
    }
    
    /// Returns `true` if the agent is currently working.
    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
    
    /// Returns `true` if the agent is idle.
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
    
    /// Returns `true` if the agent is blocked awaiting user action.
    public var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
    
    /// Associated blocked reason if in `.blocked` state, otherwise `nil`.
    public var blockedReason: BlockedReason? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }
    
    /// Associated exit code if in `.exited` state, otherwise `nil`.
    public var exitCode: ProcessExitCode? {
        if case .exited(let code) = self { return code }
        return nil
    }
    
    // MARK: - State Machine Invariant Validation & Transitions
    
    /// Validates whether a transition from `self` to `target` satisfies state machine invariants.
    public func canTransition(to target: AgentState) -> Bool {
        switch self {
        case .exited:
            // Terminal state invariant: no transitions allowed once process has terminated.
            return false
        case .idle, .working, .blocked:
            // All active states may transition between each other or terminate.
            return true
        }
    }
    
    /// Evaluates the transition to `newState` and returns the resulting state if valid,
    /// or throws `AgentStateTransitionError.invalidTransition` if invariants are violated.
    public func transition(to newState: AgentState) throws(AgentStateTransitionError) -> AgentState {
        guard canTransition(to: newState) else {
            throw .invalidTransition(from: self, to: newState)
        }
        return newState
    }
}

// MARK: - Codable Conformance

extension AgentState {
    private enum CodingKeys: String, CodingKey {
        case type
        case reason
        case code
    }
    
    private enum StateType: String, Codable {
        case idle
        case working
        case blocked
        case exited
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StateType.self, forKey: .type)
        switch type {
        case .idle:
            self = .idle
        case .working:
            self = .working
        case .blocked:
            let reason = try container.decode(BlockedReason.self, forKey: .reason)
            self = .blocked(reason: reason)
        case .exited:
            let code = try container.decode(ProcessExitCode.self, forKey: .code)
            self = .exited(code: code)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(StateType.idle, forKey: .type)
        case .working:
            try container.encode(StateType.working, forKey: .type)
        case .blocked(let reason):
            try container.encode(StateType.blocked, forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .exited(let code):
            try container.encode(StateType.exited, forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }
}
