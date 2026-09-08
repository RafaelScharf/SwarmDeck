import Testing
@testable import SwarmDeck

@Suite("AgentPreset Domain Model Tests")
struct AgentPresetTests {
    
    // MARK: - Standard Presets Tests
    
    @Test("Standard presets configuration and uniqueness")
    func testStandardPresets() {
        let shell = AgentPreset.standardShell
        #expect(shell.id == "shell")
        #expect(shell.name == "Standard Shell")
        #expect(!shell.command.isEmpty)
        #expect(shell.arguments == ["-l"])
        #expect(shell.iconName == "apple.terminal")
        #expect(shell.isValid)
        
        let claude = AgentPreset.claudeCode
        #expect(claude.id == "claude")
        #expect(claude.name == "Claude Code")
        #expect(claude.command == "claude")
        #expect(claude.iconName == "brain.head.profile")
        #expect(claude.isValid)
        
        let aider = AgentPreset.aider
        #expect(aider.id == "aider")
        #expect(aider.name == "Aider")
        #expect(aider.command == "aider")
        #expect(aider.iconName == "sparkles")
        #expect(aider.isValid)
        
        let antigravity = AgentPreset.antigravity
        #expect(antigravity.id == "antigravity")
        #expect(antigravity.name == "Antigravity")
        #expect(antigravity.command == "agy")
        #expect(antigravity.iconName == "bolt.horizontal")
        #expect(antigravity.isValid)
        
        let all = AgentPreset.allStandard
        #expect(all.count == 4)
        let uniqueIds = Set(all.map(\.id))
        #expect(uniqueIds.count == 4)
    }
    
    // MARK: - Custom Preset Factory Tests
    
    @Test("Custom preset generation")
    func testCustomPresetFactory() {
        let custom = AgentPreset.custom(
            name: "Codex CLI",
            command: "/usr/local/bin/codex",
            arguments: ["--interactive", "--model", "gpt-5"],
            workingDirectory: "/Users/dev/workspace",
            environment: ["API_KEY": "secret123"]
        )
        
        #expect(custom.id.hasPrefix("custom-"))
        #expect(custom.name == "Codex CLI")
        #expect(custom.command == "/usr/local/bin/codex")
        #expect(custom.arguments == ["--interactive", "--model", "gpt-5"])
        #expect(custom.workingDirectory == "/Users/dev/workspace")
        #expect(custom.environment["API_KEY"] == "secret123")
        #expect(custom.iconName == "slider.horizontal.3")
        #expect(custom.isValid)
    }
    
    // MARK: - Validation Tests
    
    @Test("Preset validation with empty or whitespace commands")
    func testPresetValidation() {
        let validPreset = AgentPreset(
            id: "test-1",
            name: "Valid",
            description: "Desc",
            command: "python3"
        )
        #expect(validPreset.isValid)
        
        let emptyPreset = AgentPreset(
            id: "test-2",
            name: "Empty",
            description: "Desc",
            command: ""
        )
        #expect(!emptyPreset.isValid)
        
        let whitespacePreset = AgentPreset(
            id: "test-3",
            name: "Whitespace",
            description: "Desc",
            command: "   \n\t  "
        )
        #expect(!whitespacePreset.isValid)
    }
    
    // MARK: - Equatable, Hashable, Codable Tests
    
    @Test("AgentPreset Equatable and Hashable conformance")
    func testConformances() {
        let preset1 = AgentPreset(
            id: "p1",
            name: "Test",
            description: "D",
            command: "cmd"
        )
        let preset2 = AgentPreset(
            id: "p1",
            name: "Test",
            description: "D",
            command: "cmd"
        )
        let preset3 = AgentPreset(
            id: "p2",
            name: "Test",
            description: "D",
            command: "cmd"
        )
        
        #expect(preset1 == preset2)
        #expect(preset1 != preset3)
        
        var presetSet: Set<AgentPreset> = []
        presetSet.insert(preset1)
        presetSet.insert(preset2)
        presetSet.insert(preset3)
        #expect(presetSet.count == 2)
    }
    
    @Test("AgentPreset Codable JSON roundtrip")
    func testCodableSerialization() throws {
        let original = AgentPreset(
            id: "custom-test",
            name: "Custom Agent",
            description: "A test agent preset",
            command: "agent",
            arguments: ["--flag", "val"],
            workingDirectory: "/tmp",
            environment: ["FOO": "BAR"],
            iconName: "terminal"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentPreset.self, from: data)
        
        #expect(decoded == original)
        #expect(decoded.arguments == ["--flag", "val"])
        #expect(decoded.environment == ["FOO": "BAR"])
    }
    
    // MARK: - Concurrency & Decoupling Tests
    
    @Test("AgentPreset Sendable across Task boundaries")
    func testSendableConcurrency() async {
        let preset = AgentPreset.antigravity
        let task = Task.detached { () -> AgentPreset in
            return preset
        }
        let result = await task.value
        #expect(result == preset)
    }
}
