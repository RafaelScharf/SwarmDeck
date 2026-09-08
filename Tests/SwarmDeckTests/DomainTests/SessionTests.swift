import Testing
import Foundation
@testable import SwarmDeck

@Suite("Session & SessionMetadata Domain Model Tests")
struct SessionTests {
    
    // MARK: - SessionId Tests
    
    @Test("SessionId initialization and string conversion")
    func testSessionId() {
        let id1 = SessionId()
        let id2 = SessionId()
        #expect(id1 != id2)
        
        let uuid = UUID()
        let idFromUUID = SessionId(uuid)
        #expect(idFromUUID.rawValue == uuid)
        #expect(idFromUUID.id == uuid)
        #expect(idFromUUID.description == uuid.uuidString)
        
        let validStringId = SessionId(uuidString: uuid.uuidString)
        #expect(validStringId == idFromUUID)
        
        let invalidStringId = SessionId(uuidString: "invalid-uuid-string")
        #expect(invalidStringId == nil)
    }
    
    // MARK: - SessionMetadata Tests
    
    @Test("SessionMetadata initialization and defaults")
    func testSessionMetadataDefaults() {
        let metadata = SessionMetadata(
            name: "Test Session",
            preset: .standardShell
        )
        
        #expect(metadata.name == "Test Session")
        #expect(metadata.preset == .standardShell)
        #expect(metadata.workingDirectory == nil)
        #expect(metadata.customEnvironment.isEmpty)
        #expect(metadata.createdAt <= Date())
    }
    
    @Test("SessionMetadata custom parameters and equality")
    func testSessionMetadataCustom() {
        let id = UUID()
        let date = Date()
        let metadata = SessionMetadata(
            id: id,
            name: "Claude Refactor",
            preset: .claudeCode,
            workingDirectory: "/Users/dev/repo",
            customEnvironment: ["DEBUG": "1"],
            createdAt: date
        )
        
        #expect(metadata.id == id)
        #expect(metadata.name == "Claude Refactor")
        #expect(metadata.preset == .claudeCode)
        #expect(metadata.workingDirectory == "/Users/dev/repo")
        #expect(metadata.customEnvironment["DEBUG"] == "1")
        #expect(metadata.createdAt == date)
        
        var set: Set<SessionMetadata> = []
        set.insert(metadata)
        #expect(set.contains(metadata))
    }
    
    @Test("SessionMetadata Codable serialization")
    func testSessionMetadataCodable() throws {
        let metadata = SessionMetadata(
            name: "Aider Session",
            preset: .aider,
            workingDirectory: "/tmp/project",
            customEnvironment: ["AIDER_MODEL": "claude-3-7-sonnet"]
        )
        
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(SessionMetadata.self, from: data)
        
        #expect(decoded.id == metadata.id)
        #expect(decoded.name == metadata.name)
        #expect(decoded.preset == metadata.preset)
        #expect(decoded.workingDirectory == metadata.workingDirectory)
        #expect(decoded.customEnvironment == metadata.customEnvironment)
    }
    
    // MARK: - Session Aggregate Entity Tests
    
    @Test("Session initialization and metadata extraction")
    func testSessionInitialization() {
        let session = Session(
            name: "Antigravity Agent",
            preset: .antigravity,
            workingDirectory: "/workspace",
            customEnvironment: ["AGY_ENV": "test"]
        )
        
        #expect(session.name == "Antigravity Agent")
        #expect(session.preset == .antigravity)
        #expect(session.state == .idle)
        #expect(session.processId == nil)
        #expect(session.exitCode == nil)
        
        let extractedMetadata = session.metadata
        #expect(extractedMetadata.id == session.id)
        #expect(extractedMetadata.name == session.name)
        #expect(extractedMetadata.preset == session.preset)
        #expect(extractedMetadata.workingDirectory == session.workingDirectory)
        #expect(extractedMetadata.customEnvironment == session.customEnvironment)
        #expect(extractedMetadata.createdAt == session.createdAt)
    }
    
    @Test("Session initialization from metadata")
    func testSessionInitFromMetadata() {
        let metadata = SessionMetadata(
            name: "From Metadata",
            preset: .claudeCode,
            workingDirectory: "/src"
        )
        
        let session = Session(metadata: metadata, state: .working, processId: 12345)
        #expect(session.id == metadata.id)
        #expect(session.name == "From Metadata")
        #expect(session.state == .working)
        #expect(session.processId == 12345)
    }
    
    // MARK: - Session Lifecycle State Invariant Transitions
    
    @Test("Session state transitions and exit code tracking")
    func testSessionStateTransitions() throws {
        var session = Session(name: "Worker")
        #expect(session.state == .idle)
        #expect(session.exitCode == nil)
        
        // Idle -> Working
        try session.transition(to: .working)
        #expect(session.state == .working)
        #expect(session.exitCode == nil)
        
        // Working -> Blocked
        try session.transition(to: .blocked(reason: .confirmationRequired))
        #expect(session.state == .blocked(reason: .confirmationRequired))
        
        // Blocked -> Working
        try session.transition(to: .working)
        #expect(session.state == .working)
        
        // Working -> Exited
        try session.transition(to: .exited(code: 0))
        #expect(session.state == .exited(code: 0))
        #expect(session.exitCode == ProcessExitCode.success)
        
        // Exited -> Terminal invariant check (cannot transition further)
        #expect(throws: AgentStateTransitionError.self) {
            try session.transition(to: .idle)
        }
        #expect(throws: AgentStateTransitionError.self) {
            try session.transition(to: .working)
        }
    }
    
    @Test("Session Codable serialization")
    func testSessionCodable() throws {
        var session = Session(
            name: "Persistent Session",
            preset: .standardShell,
            workingDirectory: "/Users/dev",
            processId: 9876
        )
        try session.transition(to: .blocked(reason: "Awaiting auth token"))
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Session.self, from: data)
        
        #expect(decoded.id == session.id)
        #expect(decoded.name == session.name)
        #expect(decoded.state == session.state)
        #expect(decoded.processId == session.processId)
        #expect(decoded.preset == session.preset)
    }
    
    // MARK: - Strict Swift 6 Sendable Concurrency
    
    @Test("Session and SessionMetadata Sendable across Tasks")
    func testSendableConcurrency() async {
        let session = Session(name: "Concurrent Session")
        
        let task = Task.detached { () -> Session in
            var mutated = session
            try? mutated.transition(to: .working)
            return mutated
        }
        
        let result = await task.value
        #expect(result.state == .working)
    }
}
