import Foundation
import os

/// Asynchronously harvests the user's full macOS login shell environment.
public final class ShellEnvironmentHarvester: @unchecked Sendable {
    public static let shared = ShellEnvironmentHarvester()
    
    private let cacheLock = OSAllocatedUnfairLock<[String: String]>(initialState: [:])
    private let harvestLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    
    public var cachedEnvironment: [String: String] {
        cacheLock.withLock { $0 }
    }
    
    public init() {}
    
    @discardableResult
    public func harvest() async -> [String: String] {
        let alreadyHarvested = harvestLock.withLock { isHarvesting -> Bool in
            if isHarvesting { return true }
            isHarvesting = true
            return false
        }
        if alreadyHarvested {
            return cachedEnvironment
        }
        
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let harvested = await harvestFromShell(shellPath: shellPath, timeoutSeconds: 0.8)
        
        cacheLock.withLock { env in
            for (k, v) in harvested {
                env[k] = v
            }
        }
        return cachedEnvironment
    }
    
    public func harvestFromShell(shellPath: String, timeoutSeconds: Double = 0.8) async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shellPath)
                process.arguments = ["-l", "-c", "/usr/bin/env -0 || printenv"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
                timer.schedule(deadline: .now() + timeoutSeconds)
                timer.setEventHandler {
                    if process.isRunning {
                        process.terminate()
                    }
                    timer.cancel()
                }
                timer.resume()
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timer.cancel()
                    
                    let parsed = Self.parseEnvironmentOutput(data: data)
                    continuation.resume(returning: parsed)
                } catch {
                    timer.cancel()
                    continuation.resume(returning: [:])
                }
            }
        }
    }
    
    public static func parseEnvironmentOutput(data: Data) -> [String: String] {
        guard !data.isEmpty else { return [:] }
        var result: [String: String] = [:]
        
        if data.contains(0) {
            let entries = data.split(separator: 0)
            for entryData in entries {
                guard let entry = String(data: entryData, encoding: .utf8), !entry.isEmpty else { continue }
                if let idx = entry.firstIndex(of: "=") {
                    let key = String(entry[..<idx])
                    let val = String(entry[entry.index(after: idx)...])
                    if !key.isEmpty {
                        result[key] = val
                    }
                }
            }
        } else {
            guard let text = String(data: data, encoding: .utf8) else { return [:] }
            let lines = text.components(separatedBy: .newlines)
            for line in lines {
                guard !line.isEmpty else { continue }
                if let idx = line.firstIndex(of: "=") {
                    let key = String(line[..<idx])
                    let val = String(line[line.index(after: idx)...])
                    if !key.isEmpty {
                        result[key] = val
                    }
                }
            }
        }
        return result
    }
}
