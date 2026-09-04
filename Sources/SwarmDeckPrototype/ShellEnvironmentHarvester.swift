import Foundation
import Darwin

public actor ShellEnvironmentHarvester {
    public static let shared = ShellEnvironmentHarvester()
    
    private var cachedEnvironment: [String: String]?
    
    public init() {}
    
    /// Returns the user's default login shell path.
    public func resolveUserShell() -> String {
        if let envShell = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.isExecutableFile(atPath: envShell) {
            return envShell
        }
        
        if let pwd = getpwuid(getuid()), let pwShell = pwd.pointee.pw_shell {
            let shell = String(cString: pwShell)
            if FileManager.default.isExecutableFile(atPath: shell) {
                return shell
            }
        }
        
        if FileManager.default.isExecutableFile(atPath: "/bin/zsh") {
            return "/bin/zsh"
        }
        
        return "/bin/sh"
    }
    
    /// Parses raw stdout string into a KEY=VALUE dictionary.
    /// Supports both null-delimited format (/usr/bin/env -0) and standard newline-separated format.
    public nonisolated func parseEnvironmentOutput(_ output: String) -> [String: String] {
        var env: [String: String] = [:]
        
        // 1. Check for null-delimited entries
        if output.contains("\0") {
            let entries = output.components(separatedBy: "\0")
            for entry in entries {
                if let eqIndex = entry.firstIndex(of: "=") {
                    let key = String(entry[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                    let val = String(entry[entry.index(after: eqIndex)...])
                    if !key.isEmpty {
                        env[key] = val
                    }
                }
            }
            return env
        }
        
        // 2. Standard newline-separated entries with multiline continuation support
        let lines = output.components(separatedBy: "\n")
        var currentKey: String? = nil
        var currentValue: String = ""
        
        for line in lines {
            if let eqIndex = line.firstIndex(of: "=") {
                let keyCandidate = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                
                let isValidKey = !keyCandidate.isEmpty &&
                    (keyCandidate.first!.isLetter || keyCandidate.first == "_") &&
                    keyCandidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } &&
                    !line.hasPrefix(" ") && !line.hasPrefix("\t")
                
                if isValidKey {
                    if let prevKey = currentKey {
                        env[prevKey] = currentValue
                    }
                    currentKey = keyCandidate
                    currentValue = String(line[line.index(after: eqIndex)...])
                    continue
                }
            }
            
            if let _ = currentKey {
                currentValue += "\n" + line
            }
        }
        
        if let lastKey = currentKey {
            env[lastKey] = currentValue
        }
        
        return env
    }
    
    /// Asynchronously harvests the user login shell environment with a strict timeout.
    /// Falls back gracefully to system defaults if shell execution times out or errors.
    public func harvest(
        timeout: TimeInterval = 0.8,
        forceRefresh: Bool = false,
        useInteractiveFlag: Bool = false
    ) async -> [String: String] {
        if let cached = cachedEnvironment, !forceRefresh {
            return cached
        }
        
        let shellPath = resolveUserShell()
        let cmd = "/usr/bin/env -0 2>/dev/null || printenv"
        let args = useInteractiveFlag ? ["-l", "-i", "-c", cmd] : ["-l", "-c", cmd]
        
        let harvested = await executeWithTimeout(
            executable: shellPath,
            arguments: args,
            timeout: timeout
        )
        
        var finalEnv: [String: String]
        if let rawOutput = harvested {
            finalEnv = parseEnvironmentOutput(rawOutput)
        } else {
            // Fallback: inherit current process environment
            finalEnv = ProcessInfo.processInfo.environment
        }
        
        // Merge with terminal defaults & enriched paths
        finalEnv = mergeDefaults(into: finalEnv)
        
        // Cache result
        self.cachedEnvironment = finalEnv
        
        // Update synchronous cache in ProcessEnvironment
        ProcessEnvironment.setHarvestedCache(finalEnv)
        
        return finalEnv
    }
    
    /// Merges harvested environment with terminal defaults and fallback search paths.
    public nonisolated func mergeDefaults(into env: [String: String]) -> [String: String] {
        var merged = env
        
        // Ensure TERM and COLORTERM
        if merged["TERM"] == nil || merged["TERM"]?.isEmpty == true {
            merged["TERM"] = "xterm-256color"
        }
        if merged["COLORTERM"] == nil || merged["COLORTERM"]?.isEmpty == true {
            merged["COLORTERM"] = "truecolor"
        }
        if merged["LANG"] == nil || merged["LANG"]?.isEmpty == true {
            merged["LANG"] = "en_US.UTF-8"
        }
        
        // Ensure common paths exist in PATH
        var currentPaths = (merged["PATH"] ?? "").components(separatedBy: ":").filter { !$0.isEmpty }
        let home = merged["HOME"] ?? ProcessInfo.processInfo.environment["HOME"] ?? ("~" as NSString).expandingTildeInPath
        let essentialPaths = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        
        for p in essentialPaths {
            if !currentPaths.contains(p) && FileManager.default.fileExists(atPath: p) {
                currentPaths.append(p)
            }
        }
        
        merged["PATH"] = currentPaths.joined(separator: ":")
        return merged
    }
    
    /// Spawns the subprocess and monitors it with an asynchronous deadline.
    private func executeWithTimeout(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let resolver = ContinuationResolver(continuation)
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = Pipe() // Silence stderr
            
            // Timeout watchdog timer
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                if process.isRunning {
                    process.terminate()
                    kill(process.processIdentifier, SIGKILL)
                }
                resolver.resolve(with: nil)
                timer.cancel()
            }
            timer.resume()
            
            process.terminationHandler = { proc in
                timer.cancel()
                if proc.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    resolver.resolve(with: output)
                } else {
                    resolver.resolve(with: nil)
                }
            }
            
            do {
                try process.run()
            } catch {
                timer.cancel()
                resolver.resolve(with: nil)
            }
        }
    }
    
    public func clearCache() {
        self.cachedEnvironment = nil
        ProcessEnvironment.clearHarvestedCache()
    }
    
    public func getCachedEnvironment() -> [String: String]? {
        return cachedEnvironment
    }
}

private final class ContinuationResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<String?, Never>
    
    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }
    
    func resolve(with result: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: result)
    }
}
