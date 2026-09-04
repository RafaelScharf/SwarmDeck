import Foundation

/// Utilities for resolving CLI executables and inheriting/enriching process environment variables.
public final class ProcessEnvironment: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _cachedHarvestedEnvironment: [String: String]?
    
    public static func setHarvestedCache(_ env: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        _cachedHarvestedEnvironment = env
    }
    
    public static func clearHarvestedCache() {
        lock.lock()
        defer { lock.unlock() }
        _cachedHarvestedEnvironment = nil
    }
    
    public static var cachedHarvestedEnvironment: [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        return _cachedHarvestedEnvironment
    }

    /// Returns the directories to search for binaries, combining the active PATH
    /// with common macOS directories where user CLI tools (Homebrew, uv/pip, cargo, npm) reside.
    public static func standardSearchPaths() -> [String] {
        var paths: [String] = []
        
        // 1. Inherit paths from harvested environment or existing PATH environment variable
        let pathSource = cachedHarvestedEnvironment?["PATH"] ?? ProcessInfo.processInfo.environment["PATH"]
        if let pathEnv = pathSource {
            for segment in pathEnv.components(separatedBy: ":") where !segment.isEmpty {
                if !paths.contains(segment) {
                    paths.append(segment)
                }
            }
        }
        
        // 2. Add common macOS CLI directories where AI coding agents are typically installed
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ("~" as NSString).expandingTildeInPath
        let extraCandidatePaths = [
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        
        for candidate in extraCandidatePaths {
            if !paths.contains(candidate) && FileManager.default.fileExists(atPath: candidate) {
                paths.append(candidate)
            }
        }
        
        return paths
    }
    
    /// Resolves the absolute path for a command.
    /// If the command is an absolute path or relative path with `/`, verifies that it exists and is executable.
    /// Otherwise, scans `standardSearchPaths()`.
    public static func resolveExecutablePath(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if trimmed.contains("/") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
            return nil
        }
        
        for dir in standardSearchPaths() {
            let fullPath = (dir as NSString).appendingPathComponent(trimmed)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        
        return nil
    }
    
    /// Constructs the environment dictionary for a spawned process:
    /// - Inherits all current process environment variables (shell environment, API keys like ANTHROPIC_API_KEY, OPENAI_API_KEY, etc.)
    /// - Sets PATH to the enriched standard search paths
    /// - Sets terminal capabilities: TERM=xterm-256color, COLORTERM=truecolor, LANG=en_US.UTF-8
    /// - Merges custom overrides passed by the caller
    public static func buildEnvironment(customOverrides: [String: String] = [:]) -> [String: String] {
        var env = cachedHarvestedEnvironment ?? ProcessInfo.processInfo.environment
        
        // Enforce enriched PATH
        env["PATH"] = standardSearchPaths().joined(separator: ":")
        
        // Terminal defaults
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }
        
        // Custom user overrides (API keys, presets, custom vars)
        for (key, val) in customOverrides {
            env[key] = val
        }
        
        return env
    }
}
