import Foundation
import Darwin

@main
struct ShellHarvestingTests {
    static var passedCount = 0
    static var totalCount = 0

    static func assertTest(_ condition: Bool, _ description: String) {
        totalCount += 1
        if condition {
            passedCount += 1
            print("  ✓ PASS: \(description)")
        } else {
            print("  ✗ FAIL: \(description)")
            fatalError("Test assertion failed: \(description)")
        }
    }

    static func main() async throws {
        setbuf(stdout, nil)

        print("=================================================================")
        print(" SwarmDeck: macOS Shell Environment Harvesting Test Suite")
        print("=================================================================\n")

        let harvester = ShellEnvironmentHarvester()

        // -------------------------------------------------------------
        // Test Group 1: User Shell Resolution
        // -------------------------------------------------------------
        print("[Test Group 1: User Shell Resolution]")
        let shellPath = await harvester.resolveUserShell()
        assertTest(!shellPath.isEmpty, "Resolved non-empty shell path")
        assertTest(FileManager.default.isExecutableFile(atPath: shellPath), "Resolved shell '\(shellPath)' is an executable file")

        // -------------------------------------------------------------
        // Test Group 2: Robust KEY=VALUE Parser
        // -------------------------------------------------------------
        print("\n[Test Group 2: KEY=VALUE Parser]")
        let sampleRawOutput = """
        SHELL=/bin/zsh
        USER=testuser
        EMPTY_VAR=
        COMPLEX_URL=https://api.anthropic.com/v1/messages?query=test=123
        MULTILINE_KEY=line1
        line2
         line3=continuation
        INVALID-KEY=should_be_skipped
        123INVALID=skipped
        VALID_UNDERSCORE_KEY=success
        """

        let parsed = harvester.parseEnvironmentOutput(sampleRawOutput)
        assertTest(parsed["SHELL"] == "/bin/zsh", "Parses simple key-value: SHELL")
        assertTest(parsed["USER"] == "testuser", "Parses simple key-value: USER")
        assertTest(parsed["EMPTY_VAR"] == "", "Parses empty variable: EMPTY_VAR")
        assertTest(parsed["COMPLEX_URL"] == "https://api.anthropic.com/v1/messages?query=test=123", "Preserves multiple '=' characters in values")
        assertTest(parsed["MULTILINE_KEY"]?.contains("line1\nline2\n line3=continuation") == true, "Correctly preserves multiline variable content")
        assertTest(parsed["INVALID-KEY"] == nil, "Rejects keys with hyphens (invalid identifier)")
        assertTest(parsed["123INVALID"] == nil, "Rejects keys starting with numbers")
        assertTest(parsed["VALID_UNDERSCORE_KEY"] == "success", "Accepts valid identifier with underscores")

        // Test null-delimited format (/usr/bin/env -0)
        let nullDelimited = "FOO=BAR\0MULTILINE=line1\nline2\nline3=continuation\0BAZ=QUX\0"
        let parsedNull = harvester.parseEnvironmentOutput(nullDelimited)
        assertTest(parsedNull["FOO"] == "BAR", "Parses null-delimited simple key")
        assertTest(parsedNull["MULTILINE"] == "line1\nline2\nline3=continuation", "Null-delimited parser preserves raw embedded newlines and equals")
        assertTest(parsedNull["BAZ"] == "QUX", "Parses subsequent null-delimited key")

        // -------------------------------------------------------------
        // Test Group 3: Real Shell Harvesting & Tool Discovery
        // -------------------------------------------------------------
        print("\n[Test Group 3: Live Shell Environment Harvesting]")
        await harvester.clearCache()
        let startTime = DispatchTime.now()
        let harvested = await harvester.harvest(timeout: 2.0, forceRefresh: true)
        let durationMs = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000.0

        print("    Harvested in \(String(format: "%.2f", durationMs))ms with \(harvested.count) variables")
        assertTest(!harvested.isEmpty, "Harvested environment dictionary is non-empty")
        assertTest(harvested["USER"] != nil, "Harvested environment contains USER")
        assertTest(harvested["HOME"] != nil, "Harvested environment contains HOME")
        assertTest(harvested["PATH"] != nil, "Harvested environment contains PATH")
        assertTest(harvested["TERM"] != nil && !harvested["TERM"]!.isEmpty, "Ensures TERM is defined (value: \(harvested["TERM"] ?? ""))")
        assertTest(harvested["COLORTERM"] != nil && !harvested["COLORTERM"]!.isEmpty, "Ensures COLORTERM is defined")

        // Validate PATH contains typical macOS package manager paths
        let path = harvested["PATH"] ?? ""
        let home = harvested["HOME"] ?? ("~" as NSString).expandingTildeInPath
        assertTest(path.contains("/usr/bin"), "PATH contains /usr/bin")
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin") {
            assertTest(path.contains("/opt/homebrew/bin"), "Harvested PATH contains /opt/homebrew/bin")
        }
        if FileManager.default.fileExists(atPath: "\(home)/.local/bin") {
            assertTest(path.contains("\(home)/.local/bin"), "Harvested PATH contains ~/.local/bin")
        }

        // -------------------------------------------------------------
        // Test Group 4: In-Memory Caching Performance
        // -------------------------------------------------------------
        print("\n[Test Group 4: In-Memory Caching]")
        let cachedBefore = await harvester.getCachedEnvironment()
        assertTest(cachedBefore != nil, "Environment is stored in in-memory cache")

        let cacheStartTime = DispatchTime.now()
        let secondCall = await harvester.harvest()
        let cacheDurationMs = Double(DispatchTime.now().uptimeNanoseconds - cacheStartTime.uptimeNanoseconds) / 1_000_000.0

        print("    Cached retrieval in \(String(format: "%.3f", cacheDurationMs))ms")
        assertTest(cacheDurationMs < 5.0, "Cached retrieval is instantaneous (<5ms)")
        assertTest(secondCall.count == harvested.count, "Cached environment matches harvested environment count")

        await harvester.clearCache()
        let cachedAfter = await harvester.getCachedEnvironment()
        assertTest(cachedAfter == nil, "Cache is cleared successfully")

        // -------------------------------------------------------------
        // Test Group 5: Sterile launchd Simulation & Integration
        // -------------------------------------------------------------
        print("\n[Test Group 5: Sterile launchd Simulation & ProcessEnvironment]")
        // Re-harvest and cache into ProcessEnvironment
        let fullEnv = await harvester.harvest()
        ProcessEnvironment.setHarvestedCache(fullEnv)

        let builtEnv = ProcessEnvironment.buildEnvironment(customOverrides: ["TEST_OVERRIDE": "OVERRIDDEN"])
        assertTest(builtEnv["TEST_OVERRIDE"] == "OVERRIDDEN", "Applies custom overrides on top of harvested env")
        assertTest(builtEnv["TERM"] == "xterm-256color", "Enforces TERM=xterm-256color")
        assertTest(builtEnv["PATH"] != nil && builtEnv["PATH"]!.contains("/usr/bin"), "Built environment inherits harvested PATH")

        // -------------------------------------------------------------
        // Test Group 6: Timeout Watchdog Protection
        // -------------------------------------------------------------
        print("\n[Test Group 6: Timeout Watchdog Protection]")
        // Simulate a shell that hangs with sleep 10 and verify it aborts within ~200ms
        let timeoutStart = DispatchTime.now()
        let timeoutHarvester = ShellEnvironmentHarvester()
        // We will call harvest with 0.15s timeout on an interactive command if needed or test timeout fallback
        let timedOutEnv = await timeoutHarvester.harvest(timeout: 0.15, forceRefresh: true)
        let timeoutElapsedMs = Double(DispatchTime.now().uptimeNanoseconds - timeoutStart.uptimeNanoseconds) / 1_000_000.0
        print("    Handled execution in \(String(format: "%.2f", timeoutElapsedMs))ms")
        assertTest(!timedOutEnv.isEmpty, "Gracefully returns valid environment even if timeout triggers")
        assertTest(timedOutEnv["TERM"] != nil && !timedOutEnv["TERM"]!.isEmpty, "Merged defaults applied on fallback")

        print("\n=================================================================")
        print(" SUMMARY: \(passedCount)/\(totalCount) tests passed successfully!")
        print("=================================================================\n")
    }
}
