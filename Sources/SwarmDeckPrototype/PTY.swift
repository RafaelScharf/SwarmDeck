import Foundation
import Darwin
import os

/// Configuration parameters for spawning a PTY child process.
public struct PTYConfiguration: Sendable {
    public var command: String
    public var arguments: [String]
    public var workingDirectory: String?
    public var environment: [String: String]
    
    public init(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
    
    public init(preset: AgentPreset) {
        self.command = preset.command
        self.arguments = preset.arguments
        self.workingDirectory = preset.workingDirectory
        self.environment = preset.environment
    }
}

/// POSIX errors specific to PTY spawning and lifecycle.
public enum PTYError: LocalizedError, Sendable {
    case executableNotFound(String)
    case forkFailed(Int32)
    case invalidFileDescriptor
    
    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let cmd):
            return "Executable '\(cmd)' could not be found in PATH or standard agent locations."
        case .forkFailed(let code):
            return "forkpty failed with errno \(code): \(String(cString: strerror(code)))"
        case .invalidFileDescriptor:
            return "PTY master file descriptor is invalid."
        }
    }
}

/// Actor encapsulating pseudo-terminal (PTY) master I/O and process supervision.
actor PTY {
    nonisolated let masterFD: Int32
    nonisolated let childPID: pid_t
    private let supervisor: ProcessLifecycleSupervisor
    private var readTask: Task<Void, Never>?
    private let isClosed = OSAllocatedUnfairLock(initialState: false)
    private let lastWinSize = OSAllocatedUnfairLock<winsize?>(initialState: nil)
    
    var onData: (@Sendable (Data) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?
    
    /// Spawns a new PTY child process with the given configuration.
    init(configuration: PTYConfiguration) throws {
        guard let resolvedExecutable = ProcessEnvironment.resolveExecutablePath(configuration.command) else {
            throw PTYError.executableNotFound(configuration.command)
        }
        
        let finalEnvironment = ProcessEnvironment.buildEnvironment(customOverrides: configuration.environment)
        let workingDir = configuration.workingDirectory
        
        // Pre-allocate argv and envp in parent before forkpty to guarantee
        // strictly async-signal-safe execution in the child process.
        let args = [resolvedExecutable] + configuration.arguments
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        
        let envList = finalEnvironment.map { "\($0.key)=\($0.value)" }
        var cEnv: [UnsafeMutablePointer<CChar>?] = envList.map { strdup($0) }
        cEnv.append(nil)
        
        var m: Int32 = 0
        let pid = forkpty(&m, nil, nil, nil)
        
        if pid == -1 {
            for ptr in cArgs { free(ptr) }
            for ptr in cEnv { free(ptr) }
            throw PTYError.forkFailed(errno)
        } else if pid == 0 {
            // Child process execution: only async-signal-safe operations
            signal(SIGTERM, SIG_DFL)
            signal(SIGINT, SIG_DFL)
            signal(SIGQUIT, SIG_DFL)
            signal(SIGHUP, SIG_DFL)
            signal(SIGPIPE, SIG_DFL)
            if let cwd = workingDir, !cwd.isEmpty {
                _ = chdir(cwd)
            }
            execve(resolvedExecutable, &cArgs, &cEnv)
            _exit(127)
        }
        
        // Parent process
        for ptr in cArgs { free(ptr) }
        for ptr in cEnv { free(ptr) }
        
        self.masterFD = m
        self.childPID = pid
        self.supervisor = ProcessLifecycleSupervisor(pid: pid)
    }
    
    /// Convenience initializer using an `AgentPreset` (defaults to `.standardShell`).
    init(preset: AgentPreset = .standardShell) throws {
        try self.init(configuration: PTYConfiguration(preset: preset))
    }
    
    deinit {
        readTask?.cancel()
        let shouldClose = isClosed.withLock { closed -> Bool in
            if !closed {
                closed = true
                return true
            }
            return false
        }
        if masterFD != -1 && shouldClose {
            Darwin.close(masterFD)
        }
    }
    
    /// Starts background master PTY reading and process monitoring.
    func start() {
        startReading()
        supervisor.startMonitoring { [weak self] exitCode in
            Task { [weak self] in
                await self?.handleExit(code: exitCode)
            }
        }
    }
    
    /// Compatibility helper for earlier prototype callers.
    func spawn(executable: String, arguments: [String]) throws {
        start()
    }
    
    func setOnData(_ handler: @escaping @Sendable (Data) -> Void) {
        self.onData = handler
    }
    
    func setOnExit(_ handler: @escaping @Sendable (Int32) -> Void) {
        self.onExit = handler
    }
    
    /// Gracefully terminates the child process with fallback to SIGKILL.
    @discardableResult
    func terminate() async -> Int32 {
        let code = await supervisor.terminate()
        handleExit(code: code)
        return code
    }
    
    private func handleExit(code: Int32) {
        let shouldClose = isClosed.withLock { closed -> Bool in
            if !closed {
                closed = true
                return true
            }
            return false
        }
        guard shouldClose else { return }
        
        readTask?.cancel()
        readTask = nil
        if masterFD != -1 {
            Darwin.close(masterFD)
        }
        onExit?(code)
    }
    
    private func startReading() {
        guard readTask == nil else { return }
        let fd = self.masterFD
        readTask = Task.detached { [weak self] in
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            
            while !Task.isCancelled {
                let bytesRead = Darwin.read(fd, &buffer, bufferSize)
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    if let self = self {
                        await self.handleData(data)
                    }
                } else if bytesRead == 0 {
                    break
                } else {
                    if errno == EINTR { continue }
                    break
                }
            }
        }
    }
    
    private func handleData(_ data: Data) {
        onData?(data)
    }
    
    nonisolated func writeToMaster(_ data: Data) {
        let closed = isClosed.withLock { $0 }
        guard !closed, masterFD >= 0 else { return }
        data.withUnsafeBytes { buffer in
            if let ptr = buffer.baseAddress {
                _ = Darwin.write(masterFD, ptr, buffer.count)
            }
        }
    }
    
    nonisolated func resize(columns: Int, rows: Int, widthPixels: Int, heightPixels: Int) {
        let closed = isClosed.withLock { $0 }
        guard !closed, masterFD >= 0 else { return }
        
        let cols = UInt16(clamping: max(0, columns))
        let rws = UInt16(clamping: max(0, rows))
        let wPx = UInt16(clamping: max(0, widthPixels))
        let hPx = UInt16(clamping: max(0, heightPixels))
        
        let shouldUpdate = lastWinSize.withLock { current -> Bool in
            if let cur = current,
               cur.ws_col == cols,
               cur.ws_row == rws,
               cur.ws_xpixel == wPx,
               cur.ws_ypixel == hPx {
                return false
            }
            current = winsize(ws_row: rws, ws_col: cols, ws_xpixel: wPx, ws_ypixel: hPx)
            return true
        }
        
        guard shouldUpdate else { return }
        var winSize = winsize(
            ws_row: rws,
            ws_col: cols,
            ws_xpixel: wPx,
            ws_ypixel: hPx
        )
        _ = ioctl(masterFD, TIOCSWINSZ, &winSize)
    }
    
    nonisolated func getWindowSize() -> winsize? {
        let closed = isClosed.withLock { $0 }
        guard !closed, masterFD >= 0 else {
            return lastWinSize.withLock { $0 }
        }
        var ws = winsize()
        if ioctl(masterFD, TIOCGWINSZ, &ws) == 0 {
            return ws
        }
        return lastWinSize.withLock { $0 }
    }
}
