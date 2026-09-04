import Foundation
import Darwin
import os

/// Supervises a spawned POSIX child process to detect exit and reap zombies.
public final class ProcessSupervisor: @unchecked Sendable {
    public let pid: pid_t
    private var source: DispatchSourceProcess?
    private let isMonitoring = OSAllocatedUnfairLock(initialState: false)
    private let isTerminated = OSAllocatedUnfairLock(initialState: false)
    
    public init(pid: pid_t) {
        self.pid = pid
    }
    
    deinit {
        stopMonitoring()
    }
    
    public func startMonitoring(onExit: @escaping @Sendable (Int32) -> Void) {
        let shouldStart = isMonitoring.withLock { monitoring -> Bool in
            if monitoring { return false }
            monitoring = true
            return true
        }
        guard shouldStart, pid > 0 else { return }
        
        let dispatchSource = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        
        dispatchSource.setEventHandler { [weak self] in
            guard let self = self else { return }
            var status: Int32 = 0
            let waitResult = waitpid(self.pid, &status, WNOHANG)
            
            let exitCode: Int32
            if waitResult > 0 {
                exitCode = Self.decodeExitStatus(status)
            } else {
                exitCode = 0
            }
            
            self.isTerminated.withLock { $0 = true }
            self.stopMonitoring()
            onExit(exitCode)
        }
        
        self.source = dispatchSource
        dispatchSource.resume()
    }
    
    public func stopMonitoring() {
        isMonitoring.withLock { monitoring in
            if monitoring {
                monitoring = false
                source?.cancel()
                source = nil
            }
        }
    }
    
    public static func decodeExitStatus(_ status: Int32) -> Int32 {
        if (status & 0x7F) == 0 {
            return (status >> 8) & 0xFF
        }
        if ((status & 0x7F) + 1) >> 1 > 0 {
            return 128 + (status & 0x7F)
        }
        return status
    }
    
    @discardableResult
    public func terminate(gracePeriod: TimeInterval = 1.0) async -> Int32 {
        let terminated = isTerminated.withLock { $0 }
        guard !terminated, pid > 0 else { return 0 }
        
        kill(pid, SIGTERM)
        
        let checkInterval: TimeInterval = 0.05
        var elapsed: TimeInterval = 0.0
        
        while elapsed < gracePeriod {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            elapsed += checkInterval
            
            var status: Int32 = 0
            let res = waitpid(pid, &status, WNOHANG)
            if res == pid {
                let code = Self.decodeExitStatus(status)
                isTerminated.withLock { $0 = true }
                stopMonitoring()
                return code
            } else if res == -1 && errno == ECHILD {
                isTerminated.withLock { $0 = true }
                stopMonitoring()
                return 0
            }
        }
        
        kill(pid, SIGKILL)
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
        isTerminated.withLock { $0 = true }
        stopMonitoring()
        return Self.decodeExitStatus(status)
    }
}
