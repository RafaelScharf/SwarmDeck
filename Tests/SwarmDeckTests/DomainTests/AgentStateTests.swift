import Testing
import Foundation
@testable import SwarmDeck

@Suite("AgentState Domain Model Tests")
struct AgentStateTests {
    
    // MARK: - BlockedReason Tests
    
    @Test("BlockedReason initialization and standard values")
    func testBlockedReasonBasics() {
        let customReason = BlockedReason("Custom Approval")
        #expect(customReason.rawValue == "Custom Approval")
        #expect(customReason.description == "Custom Approval")
        
        let literalReason: BlockedReason = "String Literal Reason"
        #expect(literalReason.rawValue == "String Literal Reason")
        
        #expect(BlockedReason.confirmationRequired.rawValue == "Confirmation Required")
        #expect(BlockedReason.terminalBell.rawValue == "Terminal Bell Alert")
        #expect(BlockedReason.inputRequired.rawValue == "User Input Required")
        #expect(BlockedReason.permissionRequired.rawValue == "Permission Required")
    }
    
    @Test("BlockedReason Equatable, Hashable and Codable")
    func testBlockedReasonConformances() throws {
        let reasonA = BlockedReason("Confirm")
        let reasonB = BlockedReason("Confirm")
        let reasonC = BlockedReason("Other")
        
        #expect(reasonA == reasonB)
        #expect(reasonA != reasonC)
        
        var set: Set<BlockedReason> = []
        set.insert(reasonA)
        set.insert(reasonB)
        #expect(set.count == 1)
        
        let encoded = try JSONEncoder().encode(reasonA)
        let decoded = try JSONDecoder().decode(BlockedReason.self, from: encoded)
        #expect(decoded == reasonA)
    }
    
    // MARK: - ProcessExitCode Tests
    
    @Test("ProcessExitCode basics and integer literals")
    func testProcessExitCodeBasics() {
        let codeSuccess: ProcessExitCode = 0
        #expect(codeSuccess.rawValue == 0)
        #expect(codeSuccess.isSuccess)
        #expect(!codeSuccess.isSignalTerminated)
        #expect(codeSuccess.description == "0")
        
        let codeFailure = ProcessExitCode(1)
        #expect(codeFailure.rawValue == 1)
        #expect(!codeFailure.isSuccess)
        #expect(!codeFailure.isSignalTerminated)
        
        let codeSigint = ProcessExitCode.sigint
        #expect(codeSigint.rawValue == 130)
        #expect(!codeSigint.isSuccess)
        #expect(codeSigint.isSignalTerminated)
        
        #expect(ProcessExitCode.success.rawValue == 0)
        #expect(ProcessExitCode.failure.rawValue == 1)
        #expect(ProcessExitCode.sigkill.rawValue == 137)
        #expect(ProcessExitCode.sigterm.rawValue == 143)
    }
    
    @Test("ProcessExitCode Int32 equality operators")
    func testProcessExitCodeInt32Equality() {
        let code = ProcessExitCode(42)
        #expect(code == 42)
        #expect(42 == code)
        #expect(code != 0)
        #expect(0 != code)
    }
    
    @Test("ProcessExitCode Codable")
    func testProcessExitCodeCodable() throws {
        let code = ProcessExitCode(137)
        let encoded = try JSONEncoder().encode(code)
        let decoded = try JSONDecoder().decode(ProcessExitCode.self, from: encoded)
        #expect(decoded == code)
        #expect(decoded.rawValue == 137)
    }
    
    // MARK: - AgentState Lifecycle and Predicates
    
    @Test("AgentState inspection flags and associated values")
    func testAgentStateFlags() {
        let idle = AgentState.idle
        #expect(idle.isIdle)
        #expect(!idle.isWorking)
        #expect(!idle.isBlocked)
        #expect(!idle.isTerminal)
        #expect(idle.blockedReason == nil)
        #expect(idle.exitCode == nil)
        
        let working = AgentState.working
        #expect(!working.isIdle)
        #expect(working.isWorking)
        #expect(!working.isBlocked)
        #expect(!working.isTerminal)
        
        let blocked = AgentState.blocked(reason: .confirmationRequired)
        #expect(!blocked.isIdle)
        #expect(!blocked.isWorking)
        #expect(blocked.isBlocked)
        #expect(!blocked.isTerminal)
        #expect(blocked.blockedReason == .confirmationRequired)
        
        // Test string convenience overload
        let blockedStr = AgentState.blocked(reason: "Prompt")
        #expect(blockedStr.blockedReason == BlockedReason("Prompt"))
        
        let exited = AgentState.exited(code: .success)
        #expect(!exited.isIdle)
        #expect(!exited.isWorking)
        #expect(!exited.isBlocked)
        #expect(exited.isTerminal)
        #expect(exited.exitCode == .success)
        
        // Test Int32 convenience overload
        let exitedInt = AgentState.exited(code: 1)
        #expect(exitedInt.exitCode == ProcessExitCode.failure)
    }
    
    // MARK: - State Machine Transition Invariants
    
    @Test("Valid state transitions from active states")
    func testValidActiveTransitions() throws {
        let idle = AgentState.idle
        #expect(idle.canTransition(to: .working))
        #expect(idle.canTransition(to: .blocked(reason: .inputRequired)))
        #expect(idle.canTransition(to: .exited(code: 0)))
        #expect(idle.canTransition(to: .idle))
        
        let workingResult = try idle.transition(to: .working)
        #expect(workingResult == .working)
        
        let working = AgentState.working
        #expect(working.canTransition(to: .idle))
        #expect(working.canTransition(to: .blocked(reason: .confirmationRequired)))
        #expect(working.canTransition(to: .exited(code: 1)))
        #expect(working.canTransition(to: .working))
        
        let blockedResult = try working.transition(to: .blocked(reason: .confirmationRequired))
        #expect(blockedResult == .blocked(reason: .confirmationRequired))
        
        let blocked = AgentState.blocked(reason: .confirmationRequired)
        #expect(blocked.canTransition(to: .working))
        #expect(blocked.canTransition(to: .idle))
        #expect(blocked.canTransition(to: .blocked(reason: .terminalBell)))
        #expect(blocked.canTransition(to: .exited(code: 130)))
        
        let exitedResult = try blocked.transition(to: .exited(code: 130))
        #expect(exitedResult == .exited(code: 130))
    }
    
    @Test("Terminal state invariants: exited cannot transition")
    func testTerminalStateInvariants() {
        let exited = AgentState.exited(code: .success)
        #expect(exited.isTerminal)
        
        #expect(!exited.canTransition(to: .idle))
        #expect(!exited.canTransition(to: .working))
        #expect(!exited.canTransition(to: .blocked(reason: .inputRequired)))
        #expect(!exited.canTransition(to: .exited(code: 1)))
        
        #expect(throws: AgentStateTransitionError.self) {
            try exited.transition(to: .idle)
        }
        
        #expect(throws: AgentStateTransitionError.self) {
            try exited.transition(to: .working)
        }
        
        #expect(throws: AgentStateTransitionError.self) {
            try exited.transition(to: .blocked(reason: .confirmationRequired))
        }
        
        #expect(throws: AgentStateTransitionError.self) {
            try exited.transition(to: .exited(code: 0))
        }
    }
    
    @Test("AgentStateTransitionError description")
    func testTransitionErrorDescription() {
        let error = AgentStateTransitionError.invalidTransition(from: .exited(code: 0), to: .working)
        #expect(error.description.contains("Invalid AgentState transition"))
    }
    
    // MARK: - Codable Conformance
    
    @Test("AgentState Codable serialization for all cases")
    func testAgentStateCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let states: [AgentState] = [
            .idle,
            .working,
            .blocked(reason: .confirmationRequired),
            .blocked(reason: "Awaiting SSH key passphrase"),
            .exited(code: .success),
            .exited(code: .failure),
            .exited(code: .sigint)
        ]
        
        for state in states {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(AgentState.self, from: data)
            #expect(decoded == state)
        }
    }
    
    // MARK: - Strict Concurrency Sendable Verification
    
    @Test("AgentState is safely passable across async boundaries")
    func testSendableConcurrency() async {
        let state = AgentState.blocked(reason: .permissionRequired)
        
        let task = Task.detached { () -> AgentState in
            return state
        }
        
        let result = await task.value
        #expect(result == state)
    }
}
