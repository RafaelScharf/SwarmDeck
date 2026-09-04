import Foundation

/// Lifecycle states of an AI agent or shell process.
public enum AgentState: Sendable, Equatable, Hashable {
    /// Agent or process is idling at the shell or awaiting input.
    case idle
    
    /// Agent is actively processing, running commands, or generating tokens.
    case working
    
    /// Agent is blocked and awaiting user action, confirmation prompt, or input.
    case blocked(reason: String)
    
    /// Agent process has terminated with the specified POSIX exit status code.
    case exited(code: Int32)
}
