import Foundation

/// Utilities for resolving executable binaries and constructing process environments.
public enum ProcessEnvironment {
    
    public static let standardAgentPaths: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
        "\(NSHomeDirectory())/.nvm/versions/node",
        "\(NSHomeDirectory())/.cargo/bin",
        "\(NSHomeDirectory())/.local/bin",
        "\(NSHomeDirectory())/.pyenv/shims"
    ]
    
    public static func resolveExecutablePath(_ command: String) -> String? {
        if command.hasPrefix("/") || command.hasPrefix("./") || command.hasPrefix("../") {
            let expanded = (command as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
            return nil
        }
        
        let pathVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var searchDirs = pathVar.split(separator: ":").map(String.init)
        
        for p in standardAgentPaths {
            if !searchDirs.contains(p) {
                searchDirs.append(p)
            }
        }
        
        for dir in searchDirs {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        
        return nil
    }
    
    public static func buildEnvironment(customOverrides: [String: String] = [:]) -> [String: String] {
        var env = ShellEnvironmentHarvester.shared.cachedEnvironment
        if env.isEmpty {
            env = ProcessInfo.processInfo.environment
        }
        
        let existingPath = env["PATH"] ?? ""
        var pathComponents = existingPath.split(separator: ":").map(String.init)
        for stdPath in standardAgentPaths {
            if !pathComponents.contains(stdPath) && FileManager.default.fileExists(atPath: stdPath) {
                pathComponents.append(stdPath)
            }
        }
        env["PATH"] = pathComponents.joined(separator: ":")
        
        if env["TERM"] == nil {
            env["TERM"] = "xterm-256color"
        }
        if env["COLORTERM"] == nil {
            env["COLORTERM"] = "truecolor"
        }
        if env["LANG"] == nil {
            env["LANG"] = "en_US.UTF-8"
        }
        
        for (key, value) in customOverrides {
            env[key] = value
        }
        
        return env
    }
}
