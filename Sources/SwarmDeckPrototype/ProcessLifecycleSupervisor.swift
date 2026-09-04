import Foundation
import Darwin

/// Supervises a child PTY process lifecycle:
/// - Monitors process exit via `DispatchSourceProcess`
/// - Automatically reaps terminated child processes via `waitpid` to prevent zombies
/// - Decodes POSIX exit status (normal exit code vs signal termination)
/// - Provides graceful termination with SIGTERM and automatic fallback to SIGKILL
public final class ProcessLifecycleSupervisor: @unchecked Sendable {
    public let pid: pid_t
    
    private let lock = NSLock()
    private var processSource: (any DispatchSourceProcess)?
    private var _isTerminated: Bool = false
    private var _exitCode: Int32? = nil
    private var onExitHandler: (@Sendable (Int32) -> Void)?
    
    public var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isTerminated
    }
    
    public var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return _exitCode
    }
    
    public init(pid: pid_t) {
        self.pid = pid
    }
    
    deinit {
        stopMonitoring()
        if !isTerminated && pid > 0 {
            _ = forceKill()
        }
    }
    
    /// Starts monitoring the child process for exit events.
    public func startMonitoring(onExit: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        self.onExitHandler = onExit
        lock.unlock()
        
        // Fast-path: Check if process has already exited
        var initialStatus: Int32 = 0
        let waitRes = waitpid(pid, &initialStatus, WNOHANG)
        if waitRes == pid {
            let code = decodeExitStatus(initialStatus)
            recordExit(code: code)
            return
        }
        
        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            var status: Int32 = 0
            let res = waitpid(self.pid, &status, 0)
            let code: Int32
            if res == self.pid {
                code = self.decodeExitStatus(status)
            } else if res == -1 && errno == ECHILD {
                // Already reaped
                code = self.exitCode ?? 0
            } else {
                code = self.decodeExitStatus(status)
            }
            
            self.recordExit(code: code)
        }
        
        lock.lock()
        self.processSource = source
        lock.unlock()
        
        source.resume()
    }
    
    /// Stops process monitoring.
    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        processSource?.cancel()
        processSource = nil
    }
    
    /// Gracefully terminates the child process with SIGTERM, escalating to SIGKILL if unresponsive.
    /// Returns the final exit code.
    @discardableResult
    public func terminate(gracePeriod: Duration = .milliseconds(1500)) async -> Int32 {
        if isTerminated {
            return exitCode ?? 0
        }
        
        guard pid > 0 else { return -1 }
        
        // Step 1: Send SIGTERM for graceful exit
        Darwin.kill(pid, SIGTERM)
        
        // Step 2: Poll in 50ms intervals up to gracePeriod
        let totalSteps = max(1, Int(gracePeriod.components.seconds * 20 + Int64(gracePeriod.components.attoseconds / 50_000_000_000_000_000)))
        for _ in 0..<totalSteps {
            if isTerminated {
                return exitCode ?? 0
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        
        // Step 3: Escalate to SIGKILL if child is still running
        if !isTerminated {
            return forceKill()
        }
        
        return exitCode ?? 0
    }
    
    /// Forcefully kills the child process with SIGKILL and reaps it.
    @discardableResult
    public func forceKill() -> Int32 {
        guard pid > 0 && !isTerminated else {
            return exitCode ?? 0
        }
        
        Darwin.kill(pid, SIGKILL)
        
        var status: Int32 = 0
        let res = waitpid(pid, &status, 0)
        let code: Int32
        if res == pid {
            code = decodeExitStatus(status)
        } else {
            code = 128 + SIGKILL
        }
        recordExit(code: code)
        return code
    }
    
    private func recordExit(code: Int32) {
        var callback: (@Sendable (Int32) -> Void)?
        
        lock.lock()
        guard !_isTerminated else {
            lock.unlock()
            return
        }
        _isTerminated = true
        _exitCode = code
        processSource?.cancel()
        processSource = nil
        callback = onExitHandler
        lock.unlock()
        
        callback?(code)
    }
    
    /// Decodes raw waitpid status into standard POSIX exit codes:
    /// - Normal termination: returns exit code (0-255)
    /// - Signal termination: returns 128 + signal number
    private func decodeExitStatus(_ status: Int32) -> Int32 {
        let wstatus = status & 0x7F
        if wstatus == 0 {
            // WIFEXITED: (status >> 8) & 0xFF
            return (status >> 8) & 0xFF
        } else if wstatus != 0x7F {
            // WIFSIGNALED: terminated by signal
            return 128 + wstatus
        } else {
            return status
        }
    }
}
