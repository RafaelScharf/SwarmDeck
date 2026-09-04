import Foundation
import Darwin

setbuf(stdout, nil)

print("=================================================================")
print(" SwarmDeck: Full Process Lifecycle & Spawning Test Suite")
print("=================================================================\n")

var passedCount = 0
var totalCount = 0

func assertTest(_ condition: Bool, _ description: String) {
    totalCount += 1
    if condition {
        passedCount += 1
        print("  ✓ PASS: \(description)")
    } else {
        print("  ✗ FAIL: \(description)")
        fatalError("Test assertion failed: \(description)")
    }
}

// -------------------------------------------------------------
// Test Group 1: AgentPreset Model Validation
// -------------------------------------------------------------
print("[Test Group 1: AgentPreset Model]")
let presets = AgentPreset.defaultPresets
assertTest(presets.count == 4, "Default presets include 4 agents (shell, claude, aider, agy)")
assertTest(AgentPreset.standardShell.command == "/bin/zsh", "Standard shell command is /bin/zsh")
assertTest(AgentPreset.claudeCode.command == "claude", "Claude preset command is 'claude'")
assertTest(AgentPreset.aider.command == "aider", "Aider preset command is 'aider'")
assertTest(AgentPreset.antigravity.command == "agy", "Antigravity preset command is 'agy'")

let customPreset = AgentPreset.custom(
    name: "Custom Test",
    command: "/bin/echo",
    arguments: ["Hello", "World"],
    workingDirectory: "/tmp",
    environment: ["TEST_VAR": "SWARMDECK_123"]
)
assertTest(customPreset.name == "Custom Test", "Custom preset name matches")
assertTest(customPreset.command == "/bin/echo", "Custom preset command matches")
assertTest(customPreset.arguments == ["Hello", "World"], "Custom preset arguments match")
assertTest(customPreset.workingDirectory == "/tmp", "Custom preset working directory matches")
assertTest(customPreset.environment["TEST_VAR"] == "SWARMDECK_123", "Custom preset environment matches")


// -------------------------------------------------------------
// Test Group 2: ProcessEnvironment & Binary Resolution
// -------------------------------------------------------------
print("\n[Test Group 2: ProcessEnvironment Resolution]")
let zshPath = ProcessEnvironment.resolveExecutablePath("/bin/zsh")
assertTest(zshPath == "/bin/zsh", "Resolves absolute binary path /bin/zsh")

let echoPath = ProcessEnvironment.resolveExecutablePath("echo")
assertTest(echoPath != nil && echoPath!.hasSuffix("/echo"), "Resolves system utility 'echo' via search paths")

let claudePath = ProcessEnvironment.resolveExecutablePath("claude")
print("    Found claude at: \(claudePath ?? "none")")
assertTest(claudePath != nil, "Resolves 'claude' CLI executable from search paths (~/.local/bin)")

let agyPath = ProcessEnvironment.resolveExecutablePath("agy")
print("    Found agy at: \(agyPath ?? "none")")
assertTest(agyPath != nil, "Resolves 'agy' CLI executable from search paths (~/.local/bin)")

let nonExistentPath = ProcessEnvironment.resolveExecutablePath("non_existent_binary_xyz_12345")
assertTest(nonExistentPath == nil, "Returns nil for non-existent executable")

let builtEnv = ProcessEnvironment.buildEnvironment(customOverrides: ["SWARM_KEY": "SECRET_999"])
assertTest(builtEnv["TERM"] == "xterm-256color", "Enforces TERM=xterm-256color")
assertTest(builtEnv["COLORTERM"] == "truecolor", "Enforces COLORTERM=truecolor")
assertTest(builtEnv["SWARM_KEY"] == "SECRET_999", "Merges custom environment overrides")
assertTest(builtEnv["PATH"] != nil && builtEnv["PATH"]!.contains(".local/bin"), "Enriched PATH includes .local/bin")


// -------------------------------------------------------------
// Test Group 3: Process Lifecycle Monitoring & Exit Detection
// -------------------------------------------------------------
print("\n[Test Group 3: Lifecycle Supervisor & Exit Detection]")

func runPTYExitCodeTest(expectedCode: Int32) async {
    do {
        let config = PTYConfiguration(command: "/bin/sh", arguments: ["-c", "exit \(expectedCode)"])
        let pty = try PTY(configuration: config)
        let pid = pty.childPID
        assertTest(pid > 0, "Spawned child PID \(pid) for exit code \(expectedCode)")
        
        let exitStream = AsyncStream<Int32> { cont in
            Task {
                await pty.setOnExit { code in
                    cont.yield(code)
                    cont.finish()
                }
                await pty.start()
            }
        }
        
        var capturedCode: Int32? = nil
        for await code in exitStream {
            capturedCode = code
        }
        
        assertTest(capturedCode == expectedCode, "PTY accurately detected process exit code \(expectedCode)")
        
        // Zombie verification: child must be reaped
        var status: Int32 = 0
        let reaped = waitpid(pid, &status, WNOHANG)
        assertTest(reaped == -1 && errno == ECHILD, "Child PID \(pid) was properly reaped (no zombie)")
        _ = pty
    } catch {
        fatalError("Exit code test failed: \(error)")
    }
}

func runPTYTerminationTest() async {
    do {
        let config = PTYConfiguration(command: "/bin/sleep", arguments: ["10"])
        let pty = try PTY(configuration: config)
        let pid = pty.childPID
        assertTest(pid > 0, "Spawned sleep child PID \(pid) for termination test")
        
        let exitStream = AsyncStream<Int32> { cont in
            Task {
                await pty.setOnExit { code in
                    cont.yield(code)
                    cont.finish()
                }
                await pty.start()
            }
        }
        
        try? await Task.sleep(for: .milliseconds(150))
        let finalCode = await pty.terminate()
        assertTest(finalCode == 128 + SIGTERM || finalCode == 128 + SIGKILL, "Graceful termination killed child with signal (got \(finalCode))")
        
        var capturedCode: Int32? = nil
        for await code in exitStream {
            capturedCode = code
        }
        assertTest(capturedCode == finalCode, "Exit callback received matching terminated code \(finalCode)")
        
        // Zombie verification
        var status: Int32 = 0
        let reaped = waitpid(pid, &status, WNOHANG)
        assertTest(reaped == -1 && errno == ECHILD, "Terminated child PID \(pid) was properly reaped (no zombie)")
        _ = pty
    } catch {
        fatalError("Termination test failed: \(error)")
    }
}

// -------------------------------------------------------------
// Test Group 4: PTY Spawning with Custom CWD & Environment
// -------------------------------------------------------------
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    
    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }
    
    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

func runPTYSpawnTest() async {
    print("\n[Test Group 4: PTY Custom CWD and Environment]")
    do {
        let tempDir = NSTemporaryDirectory()
        let config = PTYConfiguration(
            command: "/bin/sh",
            arguments: ["-c", "echo CWD=$(pwd); echo FOO=$FOO; exit 33"],
            workingDirectory: tempDir,
            environment: ["FOO": "BAR_SWARMDECK"]
        )
        
        let pty = try PTY(configuration: config)
        let pid = pty.childPID
        assertTest(pid > 0, "PTY spawned child process with PID \(pid)")
        
        let collector = OutputCollector()
        let exitStream = AsyncStream<Int32> { cont in
            Task {
                await pty.setOnData { data in
                    collector.append(data)
                }
                await pty.setOnExit { code in
                    cont.yield(code)
                    cont.finish()
                }
                await pty.start()
            }
        }
        
        var exitCode: Int32? = nil
        for await code in exitStream {
            exitCode = code
        }
        
        assertTest(exitCode == 33, "PTY process exited with expected custom exit code 33")
        
        let outputString = collector.string()
        print("    Captured output: \(outputString.trimmingCharacters(in: .whitespacesAndNewlines))")
        assertTest(outputString.contains("FOO=BAR_SWARMDECK"), "Child process correctly inherited custom environment variable")
        let resolvedTemp = URL(fileURLWithPath: tempDir).resolvingSymlinksInPath().path
        assertTest(outputString.contains(resolvedTemp), "Child process correctly executed in custom workingDirectory (\(resolvedTemp))")
        _ = pty
    } catch {
        fatalError("PTY test failed with error: \(error)")
    }
}

Task {
    await runPTYExitCodeTest(expectedCode: 0)
    await runPTYExitCodeTest(expectedCode: 42)
    await runPTYTerminationTest()
    await runPTYSpawnTest()
    
    print("\n=================================================================")
    print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
    print("=================================================================\n")
    exit(0)
}

dispatchMain()
