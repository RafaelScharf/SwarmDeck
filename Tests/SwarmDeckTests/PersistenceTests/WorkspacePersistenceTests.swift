import Testing
@testable import SwarmDeck

@Suite("Workspace Persistence & Crash Recovery Tests")
struct WorkspacePersistenceTests {
    
    // MARK: - Test Environment Helpers
    
    private func makeTemporaryService(debounceMs: Int = 100) -> (WorkspacePersistenceService, URL) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwarmDeckTests-\(UUID().uuidString)", isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("workspace.json")
        let tempFileURL = tempDir.appendingPathComponent("workspace.json.tmp")
        let service = WorkspacePersistenceService(
            fileURL: fileURL,
            tempFileURL: tempFileURL,
            debounceInterval: .milliseconds(debounceMs)
        )
        return (service, tempDir)
    }
    
    private func cleanupDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - 1. JSON Codable Serialization & Roundtrip
    
    @Test("WorkspaceTopology Codable serialization and roundtrip")
    func testTopologySerializationRoundtrip() throws {
        let session1 = Session(
            name: "Shell 1",
            preset: .standardShell,
            workingDirectory: "/Users/dev/workspace",
            customEnvironment: ["ENV": "production"]
        )
        
        var session2 = Session(
            name: "Claude Code",
            preset: .claudeCode,
            workingDirectory: "/tmp/project"
        )
        try session2.transition(to: .working)
        
        var session3 = Session(
            name: "Aider Assistant",
            preset: .aider
        )
        try session3.transition(to: .blocked(reason: .confirmationRequired))
        
        var session4 = Session(
            name: "Antigravity Batch",
            preset: .antigravity
        )
        try session4.transition(to: .exited(code: 0))
        
        let topology = WorkspaceTopology(
            version: 1,
            sessions: [session1, session2, session3, session4],
            selectedSessionId: session2.id,
            lastSavedAt: Date(),
            cleanShutdown: false
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(topology)
        #expect(!data.isEmpty)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let decoded = try decoder.decode(WorkspaceTopology.self, from: data)
        #expect(decoded.version == 1)
        #expect(decoded.sessions.count == 4)
        #expect(decoded.selectedSessionId == session2.id)
        #expect(decoded.cleanShutdown == false)
        
        #expect(decoded.sessions[0].name == "Shell 1")
        #expect(decoded.sessions[0].preset == .standardShell)
        #expect(decoded.sessions[0].state == .idle)
        #expect(decoded.sessions[0].workingDirectory == "/Users/dev/workspace")
        #expect(decoded.sessions[0].customEnvironment["ENV"] == "production")
        
        #expect(decoded.sessions[1].name == "Claude Code")
        #expect(decoded.sessions[1].state == .working)
        
        #expect(decoded.sessions[2].name == "Aider Assistant")
        #expect(decoded.sessions[2].state == .blocked(reason: .confirmationRequired))
        
        #expect(decoded.sessions[3].name == "Antigravity Batch")
        #expect(decoded.sessions[3].state == .exited(code: 0))
    }
    
    // MARK: - 2. Atomic File Writes
    
    @Test("Atomic write creates target file and does not leave temporary file behind")
    func testAtomicFileWrite() async throws {
        let (service, tempDir) = makeTemporaryService()
        defer { cleanupDirectory(tempDir) }
        
        let session = Session(name: "Test Shell", preset: .standardShell)
        let topology = WorkspaceTopology(
            version: 1,
            sessions: [session],
            selectedSessionId: session.id,
            cleanShutdown: false
        )
        
        try await service.saveImmediately(topology)
        
        let fileManager = FileManager.default
        let fileURL = await service.fileURL
        let tempFileURL = await service.tempFileURL
        
        #expect(fileManager.fileExists(atPath: fileURL.path))
        #expect(!fileManager.fileExists(atPath: tempFileURL.path))
        
        let loaded = try await service.loadTopology()
        #expect(loaded != nil)
        #expect(loaded?.sessions.count == 1)
        #expect(loaded?.sessions.first?.name == "Test Shell")
        #expect(loaded?.selectedSessionId == session.id)
    }
    
    // MARK: - 3. Debounced Persistence
    
    @Test("Debounced save coalesces rapid updates into final state")
    func testDebouncedSaveCoalescing() async throws {
        let (service, tempDir) = makeTemporaryService(debounceMs: 150)
        defer { cleanupDirectory(tempDir) }
        
        // Schedule multiple rapid saves
        for i in 1...5 {
            let session = Session(name: "Session Update \(i)", preset: .standardShell)
            let topology = WorkspaceTopology(sessions: [session])
            await service.scheduleSave(topology: topology)
            try? await Task.sleep(for: .milliseconds(20))
        }
        
        // Wait for debounce window to elapse
        try await Task.sleep(for: .milliseconds(250))
        
        let loaded = try await service.loadTopology()
        #expect(loaded != nil)
        #expect(loaded?.sessions.count == 1)
        #expect(loaded?.sessions.first?.name == "Session Update 5")
    }
    
    @Test("Flush forces immediate write of pending debounced save")
    func testFlushImmediateWrite() async throws {
        let (service, tempDir) = makeTemporaryService(debounceMs: 5000) // Long debounce
        defer { cleanupDirectory(tempDir) }
        
        let session = Session(name: "Immediate Flushed Session", preset: .standardShell)
        let topology = WorkspaceTopology(sessions: [session])
        
        await service.scheduleSave(topology: topology)
        try await service.flush()
        
        let loaded = try await service.loadTopology()
        #expect(loaded != nil)
        #expect(loaded?.sessions.first?.name == "Immediate Flushed Session")
    }
    
    // MARK: - 4. Corrupted File Fallback Recovery
    
    @Test("Corrupted JSON file triggers fallback recovery and backup creation")
    func testCorruptedFileFallbackRecovery() async throws {
        let (service, tempDir) = makeTemporaryService()
        defer { cleanupDirectory(tempDir) }
        
        let fileManager = FileManager.default
        let fileURL = await service.fileURL
        
        // Ensure directory exists
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Write corrupted non-JSON content
        let corruptedPayload = "{\"version\": 1, \"sessions\": [MALFORMED_CORRUPTED_JSON_DATA...".data(using: .utf8)!
        try corruptedPayload.write(to: fileURL)
        
        // loadTopology() should throw deserialization error
        await #expect(throws: WorkspacePersistenceError.self) {
            try await service.loadTopology()
        }
        
        // loadWithRecovery() should handle gracefully
        let (recoveredTopology, wasCorrupted) = await service.loadWithRecovery()
        #expect(wasCorrupted == true)
        #expect(recoveredTopology.sessions.isEmpty)
        
        // Original corrupted file should have been moved to a backup file
        #expect(!fileManager.fileExists(atPath: fileURL.path))
        
        let contents = try fileManager.contentsOfDirectory(atPath: tempDir.path)
        let backupFiles = contents.filter { $0.hasPrefix("workspace.json.corrupted-") }
        #expect(backupFiles.count == 1)
    }
    
    @Test("Zero-byte empty file handled as corrupted with fallback recovery")
    func testZeroByteEmptyFileRecovery() async throws {
        let (service, tempDir) = makeTemporaryService()
        defer { cleanupDirectory(tempDir) }
        
        let fileManager = FileManager.default
        let fileURL = await service.fileURL
        
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data().write(to: fileURL) // Zero bytes
        
        let (recoveredTopology, wasCorrupted) = await service.loadWithRecovery()
        #expect(wasCorrupted == true)
        #expect(recoveredTopology.sessions.isEmpty)
    }
    
    @Test("Missing file returns default empty topology without corruption flag")
    func testMissingFileReturnsCleanDefault() async {
        let (service, tempDir) = makeTemporaryService()
        defer { cleanupDirectory(tempDir) }
        
        let (topology, wasCorrupted) = await service.loadWithRecovery()
        #expect(wasCorrupted == false)
        #expect(topology.sessions.isEmpty)
    }
    
    // MARK: - 5. Clean Shutdown vs Crash Detection
    
    @Test("Clean shutdown records flag and timestamp")
    func testCleanShutdownRecording() async throws {
        let (service, tempDir) = makeTemporaryService()
        defer { cleanupDirectory(tempDir) }
        
        let session = Session(name: "Orderly Exit", preset: .standardShell)
        let topology = WorkspaceTopology(sessions: [session], cleanShutdown: false)
        
        try await service.recordCleanShutdown(topology: topology)
        
        let loaded = try await service.loadTopology()
        #expect(loaded?.cleanShutdown == true)
    }
    
    // MARK: - 6. AutoRestartPolicy & Preset Safety
    
    @Test("AgentPreset safety evaluation for auto-restart")
    func testAgentPresetAutoRestartSafety() {
        #expect(AgentPreset.standardShell.isSafeForAutoRestart == true)
        #expect(AgentPreset.claudeCode.isSafeForAutoRestart == false)
        #expect(AgentPreset.aider.isSafeForAutoRestart == false)
        #expect(AgentPreset.antigravity.isSafeForAutoRestart == false)
        
        let customShell = AgentPreset(id: "shell", name: "Custom Zsh", description: "", command: "/bin/zsh")
        #expect(customShell.isSafeForAutoRestart == true)
        
        let customScript = AgentPreset(id: "custom-build", name: "Build Runner", description: "", command: "make")
        #expect(customScript.isSafeForAutoRestart == false)
    }
    
    @Test("AutoRestartPolicy enumeration and cases")
    func testAutoRestartPolicyCases() {
        #expect(AutoRestartPolicy.allCases.contains(.disabled))
        #expect(AutoRestartPolicy.allCases.contains(.safePresetsOnly))
        #expect(AutoRestartPolicy.allCases.contains(.allPresets))
    }
    
    // MARK: - 7. SessionStore Integration & Restoration
    
    @Test("AgentSession toSession conversion preserves identity and state")
    @MainActor
    func testAgentSessionToSessionConversion() {
        let agentSession = AgentSession(
            name: "My Agent",
            preset: .aider,
            workingDirectory: "/Users/dev/code",
            customEnvironment: ["KEY": "VAL"]
        )
        agentSession.state = .working
        agentSession.pid = 4321
        agentSession.exitCode = 0
        
        let session = agentSession.toSession()
        #expect(session.id == agentSession.id)
        #expect(session.name == "My Agent")
        #expect(session.preset == .aider)
        #expect(session.workingDirectory == "/Users/dev/code")
        #expect(session.customEnvironment["KEY"] == "VAL")
        #expect(session.state == .working)
        #expect(session.processId == 4321)
        #expect(session.exitCode == ProcessExitCode.success)
    }
    
    @Test("SessionStore workspace restoration with disabled auto-restart leaves sessions idle")
    @MainActor
    func testSessionStoreRestorationDisabledPolicy() async throws {
        let (service, tempDir) = makeTemporaryService()
        defer { cleanupDirectory(tempDir) }
        
        let store = SessionStore()
        store.persistenceService = service
        
        let session1 = Session(name: "Restored Shell", preset: .standardShell)
        let session2 = Session(name: "Restored Claude", preset: .claudeCode)
        let topology = WorkspaceTopology(
            version: 1,
            sessions: [session1, session2],
            selectedSessionId: session2.id
        )
        try await service.saveImmediately(topology)
        
        let (count, wasCorrupted) = await store.restoreWorkspace(policy: .disabled)
        #expect(count == 2)
        #expect(wasCorrupted == false)
        #expect(store.sessions.count == 2)
        #expect(store.selectedSessionId == session2.id)
        #expect(store.sessions[0].name == "Restored Shell")
        #expect(store.sessions[0].state == .idle)
        #expect(store.sessions[1].name == "Restored Claude")
        #expect(store.sessions[1].state == .idle)
    }
}
