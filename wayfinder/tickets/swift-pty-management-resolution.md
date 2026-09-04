---
type: research-resolution
ticket: swift-pty-management
status: resolved
date: 2026-09-03
---

# Resolution: Robust PTY Management in Modern Swift & Swift Concurrency

## 1. Executive Summary

Managing background pseudo-terminals (PTYs) in macOS using native Swift requires bridging POSIX-level Darwin APIs with Swift Concurrency (`actor`, `AsyncStream`, and `withCheckedContinuation`). 

While naive implementations typically wrap `Foundation.Process` with `FileHandle.readabilityHandler` or `FileHandle.availableData`, **this pattern contains critical stability flaws on macOS**:
1. **The `EIO` Crash Trap:** When a child process terminates, the macOS Darwin kernel reports an `EIO` (Input/output error) on the master PTY descriptor. `FileHandle.availableData` converts this into an Objective-C `NSFileHandleOperationException` which **cannot be caught with Swift `do-catch`**, abruptly crashing the entire host application.
2. **The Slave Descriptor Leak:** If the parent process fails to explicitly close its own copy of the slave file descriptor immediately after `process.run()`, the PTY master will never encounter `EOF` or `EIO`, causing reader streams to hang indefinitely.
3. **Thread Blocking & Race Hazards:** Closing a file descriptor while a GCD dispatch source is actively monitoring it triggers kernel race conditions (`EBADDESC`). The descriptor must be closed strictly inside `source.setCancelHandler`.
4. **GUI Environment Blindness:** macOS applications launched from Finder/Dock do not inherit the user's interactive shell `$PATH`. Subprocesses running CLI tools (Node.js, Python, Claude Code, Aider) will fail with "command not found" unless the environment is properly seeded or spawned via a login shell.

Below is the definitive, production-grade architecture for spawning, streaming, and managing PTY processes safely in SwarmDeck.

---

## 2. Low-Level PTY Allocation & Process Spawning

### 2.1 PTY Pair Allocation (`openpty` vs `posix_openpt`)
On macOS (Darwin), two API families exist for creating pseudo-terminal pairs:
* **`posix_openpt` + `grantpt` + `unlockpt` + `ptsname` + `open`:** Standard POSIX/Unix98 mechanism. Requires 5 separate system calls and manual path querying.
* **`openpty(&masterFD, &slaveFD, nil, nil, &winsize)`:** Available via `import Darwin` (libutil). Automatically performs master allocation, permission granting, slave unlocking, slave path resolution, and slave opening in a single atomic C call. Furthermore, it allows passing initial window dimensions (`struct winsize`).

**Recommendation:** Use `openpty()`. It is standard on BSD/macOS systems, concise, and atomic.

### 2.2 Terminal Attributes & Window Sizing
Before spawning the child process, set the initial window size so terminal utilities (which query `TIOCGWINSZ`) know their boundaries immediately:
```swift
var ws = winsize(
    ws_row: UInt16(rows),
    ws_col: UInt16(cols),
    ws_xpixel: 0,
    ws_ypixel: 0
)
openpty(&masterFD, &slaveFD, nil, nil, &ws)
```

Dynamic window resizing while the process is active is achieved via `ioctl(masterFD, TIOCSWINSZ, &ws)`. This causes the kernel terminal driver to automatically broadcast `SIGWINCH` (Window Change) to the child foreground process group.

### 2.3 The Slave Descriptor Lifecycle (Critical Rule)
When using `Foundation.Process`:
```swift
let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
process.standardInput = slaveHandle
process.standardOutput = slaveHandle
process.standardError = slaveHandle
try process.run()

// CRITICAL STEP: Close the parent's copy of slaveFD immediately!
close(slaveFD)
```
*Why?* When `process.run()` is called, the child process inherits file descriptors. If the parent process keeps `slaveFD` open, the kernel sees that an active writer still holds the slave end. When the child process exits, the master PTY will **never signal EOF/EIO** because the parent itself is still holding the slave open! Closing `slaveFD` immediately after `run()` ensures that when the child terminates, the last slave descriptor closes, correctly triggering termination on `masterFD`.

---

## 3. Swift Concurrency & Non-Blocking Stream I/O

### 3.1 Why `FileHandle` Fails for PTYs
* `FileHandle.availableData` throws `NSFileHandleOperationException` on macOS when the child exits (due to Darwin `EIO`). Because this is an `NSException`, Swift `do-catch` blocks cannot catch it, crashing the app.
* `FileHandle.bytes` (AsyncSequence) can block underlying cooperative thread pool threads or buffer unpredictable chunk sizes.
* `FileHandle.read(upToCount:)` is synchronous and blocks the thread.

### 3.2 The Modern Solution: `DispatchSourceRead` + `AsyncStream<Data>`
The optimal pattern combines:
1. Setting `O_NONBLOCK` on `masterFD`.
2. Monitoring readability with `DispatchSource.makeReadSource(fileDescriptor:queue:)`.
3. Wrapping the event handler into an `AsyncStream<Data>`.
4. Handling `EIO` as normal EOF.
5. Closing `masterFD` strictly inside `setCancelHandler`.

```swift
let flags = fcntl(masterFD, F_GETFL)
_ = fcntl(masterFD, F_SETFL, flags | O_NONBLOCK)

let (stream, continuation) = AsyncStream<Data>.makeStream()
let ioQueue = DispatchQueue(label: "com.swarmdeck.pty.read", qos: .userInteractive)
let readSource = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: ioQueue)

readSource.setEventHandler {
    var buffer = [UInt8](repeating: 0, count: 16384)
    while true {
        let bytesRead = Darwin.read(masterFD, &buffer, buffer.count)
        if bytesRead > 0 {
            continuation.yield(Data(buffer[0..<bytesRead]))
            if bytesRead < buffer.count { break } // Drained available buffer
        } else if bytesRead == 0 {
            // EOF reached
            readSource.cancel()
            continuation.finish()
            break
        } else {
            let err = errno
            if err == EAGAIN || err == EWOULDBLOCK {
                break // No more data right now; wait for next event
            } else if err == EIO {
                // macOS PTY: Child process terminated and closed slave FD
                readSource.cancel()
                continuation.finish()
                break
            } else if err == EINTR {
                continue // System call interrupted by signal, retry
            } else {
                readSource.cancel()
                continuation.finish()
                break
            }
        }
    }
}

// SAFE TEARDOWN: Never close masterFD before the dispatch source is fully cancelled!
readSource.setCancelHandler {
    Darwin.close(masterFD)
}

continuation.onTermination = { @Sendable _ in
    readSource.cancel()
}

readSource.resume()
```

### 3.3 Asynchronous Non-Blocking Writes & `SIGPIPE`
Writing user input or programmatic commands into the PTY:
1. **SIGPIPE Defense:** By default, writing to a closed pipe or master PTY whose child died raises `SIGPIPE`, terminating the application. We must ignore `SIGPIPE` at startup:
   ```swift
   _ = signal(SIGPIPE, SIG_IGN)
   ```
2. **Actor Isolation:** Performing writes inside an `actor` prevents interleaving when multiple tasks attempt to send input simultaneously.

---

## 4. Process Lifecycle, Signals & Cleanup

### 4.1 Signaling & Process Groups
AI agent sessions (such as Claude Code or Aider) run complex child process trees (spawning `node`, `python`, `git`, `bash`, compilers).
* **Terminal Signals (Ctrl+C, Ctrl+D):** In a PTY, sending byte `0x03` (`\u{03}` / ETX) to `masterFD` causes the kernel line discipline (`termios` `VINTR`) to automatically emit `SIGINT` to the child's foreground process group. Byte `0x04` (`\u{04}`) sends EOF (`VEOF`).
* **Process Group Termination:** When terminating a session, calling `process.terminate()` only sends `SIGTERM` to the immediate child process, potentially leaving orphan grandchild processes running. To prevent orphaned processes, SwarmDeck targets the process group:
  ```swift
  let pid = process.processIdentifier
  // Send SIGTERM to entire process group
  kill(-pid, SIGTERM)
  ```

### 4.2 Graceful Escalation Pattern
When shutting down an agent session:
1. **Stage 1 (Soft):** Send `SIGINT` (`\u{03}` into master PTY or `kill(-pid, SIGINT)`). Wait 1.0s.
2. **Stage 2 (Terminate):** Send `SIGTERM` (`kill(-pid, SIGTERM)`). Wait 2.0s.
3. **Stage 3 (Force):** Send `SIGKILL` (`kill(-pid, SIGKILL)`).

### 4.3 Asynchronous Exit Awaiting (`withCheckedContinuation`)
Calling `process.waitUntilExit()` synchronously blocks the executing thread. In Swift Concurrency, we wrap `process.terminationHandler`:
```swift
func waitUntilExit() async -> Int32 {
    if !process.isRunning {
        return process.terminationStatus
    }
    return await withCheckedContinuation { continuation in
        process.terminationHandler = { proc in
            continuation.resume(returning: proc.terminationStatus)
        }
    }
}
```

---

## 5. macOS GUI Application Environment Considerations

When SwarmDeck is packaged as a macOS `.app` bundle and opened via Finder, Dock, or Spotlight, it inherits a bare environment from `launchd`:
* `PATH` is stripped to `/usr/bin:/bin:/usr/sbin:/sbin`.
* Node, Python, Homebrew (`/opt/homebrew/bin`), Cargo (`~/.cargo/bin`), and version managers (`fnm`, `nvm`, `asdf`) are missing.

### Solution: Spawn via Login Shell
To ensure all user environment variables, PATH extensions, and tool configurations are loaded seamlessly, SwarmDeck should launch commands through the user's configured login shell (`$SHELL -l -c "exec <command>"`):
```swift
let userShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
process.executableURL = URL(fileURLWithPath: userShell)
process.arguments = ["-l", "-c", "exec \(command)"]
```
Standard terminal variables must also be explicitly seeded:
* `TERM`: `xterm-256color`
* `COLORTERM`: `truecolor`
* `LANG`: `en_US.UTF-8`

---

## 6. Complete Production Reference Implementation

Here is the ready-to-use, thread-safe, actor-isolated `PTYProcess` implementation for SwarmDeck:

```swift
import Foundation
import Darwin

public enum PTYError: Error, LocalizedError {
    case openptyFailed(errno: Int32)
    case invalidFileDescriptor
    case processNotRunning
    case ioctlFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case pipeBroken
    
    public var errorDescription: String? {
        switch self {
        case .openptyFailed(let err): return "Failed to open PTY (errno: \(err))"
        case .invalidFileDescriptor: return "Invalid file descriptor"
        case .processNotRunning: return "Process is not running"
        case .ioctlFailed(let err): return "PTY ioctl failed (errno: \(err))"
        case .writeFailed(let err): return "PTY write failed (errno: \(err))"
        case .pipeBroken: return "Broken pipe writing to PTY"
        }
    }
}

public struct TerminalDimensions: Sendable {
    public var cols: Int
    public var rows: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    
    public init(cols: Int = 80, rows: Int = 24, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.cols = cols
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public actor PTYProcess {
    private let process: Process
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var exitContinuation: CheckedContinuation<Int32, Never>?
    
    public nonisolated let outputStream: AsyncStream<Data>
    private let outputContinuation: AsyncStream<Data>.Continuation
    
    public var isRunning: Bool {
        return process.isRunning
    }
    
    public var processIdentifier: Int32 {
        return process.processIdentifier
    }
    
    public init(
        executableURL: URL,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        dimensions: TerminalDimensions = TerminalDimensions()
    ) throws {
        // 1. Ignore SIGPIPE globally
        _ = signal(SIGPIPE, SIG_IGN)
        
        // 2. Prepare AsyncStream for output
        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingNewest(1000)
        )
        self.outputStream = stream
        self.outputContinuation = continuation
        
        // 3. Allocate PTY pair
        var master: Int32 = 0
        var slave: Int32 = 0
        var ws = winsize(
            ws_row: UInt16(dimensions.rows),
            ws_col: UInt16(dimensions.cols),
            ws_xpixel: UInt16(dimensions.pixelWidth),
            ws_ypixel: UInt16(dimensions.pixelHeight)
        )
        
        guard openpty(&master, &slave, nil, nil, &ws) == 0 else {
            continuation.finish()
            throw PTYError.openptyFailed(errno: errno)
        }
        
        // Set master FD to non-blocking
        let flags = fcntl(master, F_GETFL)
        if flags != -1 {
            _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        }
        self.masterFD = master
        
        // 4. Configure Process
        let proc = Process()
        proc.executableURL = executableURL
        proc.arguments = arguments
        proc.currentDirectoryURL = currentDirectoryURL
        
        // Merge environment with standard terminal defaults
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"
        if let customEnv = environment {
            env.merge(customEnv) { _, new in new }
        }
        proc.environment = env
        
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle
        self.process = proc
        
        // 5. Start process
        try proc.run()
        
        // 6. CRITICAL: Parent process must close slaveFD immediately after run!
        close(slave)
        
        // 7. Setup non-blocking DispatchSource reader
        let queue = DispatchQueue(
            label: "com.swarmdeck.pty.read.\(proc.processIdentifier)",
            qos: .userInteractive
        )
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 16384)
            while true {
                let bytesRead = Darwin.read(master, &buffer, buffer.count)
                if bytesRead > 0 {
                    continuation.yield(Data(buffer[0..<bytesRead]))
                    if bytesRead < buffer.count { break }
                } else if bytesRead == 0 {
                    source.cancel()
                    continuation.finish()
                    break
                } else {
                    let err = errno
                    if err == EAGAIN || err == EWOULDBLOCK {
                        break
                    } else if err == EIO {
                        // macOS PTY: Child closed slave side
                        source.cancel()
                        continuation.finish()
                        break
                    } else if err == EINTR {
                        continue
                    } else {
                        source.cancel()
                        continuation.finish()
                        break
                    }
                }
            }
        }
        
        // Safe file descriptor teardown
        source.setCancelHandler {
            Darwin.close(master)
        }
        
        continuation.onTermination = { @Sendable _ in
            source.cancel()
        }
        
        self.readSource = source
        source.resume()
    }
    
    /// Sends raw bytes / input to the terminal process.
    public func write(_ data: Data) throws {
        guard masterFD != -1 else { throw PTYError.invalidFileDescriptor }
        guard process.isRunning else { throw PTYError.processNotRunning }
        
        var remaining = data
        while !remaining.isEmpty {
            let bytesWritten = remaining.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return Darwin.write(masterFD, base, ptr.count)
            }
            
            if bytesWritten > 0 {
                remaining = remaining.dropFirst(bytesWritten)
            } else {
                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK {
                    // Small delay if the kernel PTY buffer is saturated
                    Thread.sleep(forTimeInterval: 0.001)
                    continue
                } else if err == EINTR {
                    continue
                } else if err == EPIPE || err == EIO {
                    throw PTYError.pipeBroken
                } else {
                    throw PTYError.writeFailed(errno: err)
                }
            }
        }
    }
    
    /// Convenient string writer (UTF-8).
    public func write(_ string: String) throws {
        if let data = string.data(using: .utf8) {
            try write(data)
        }
    }
    
    /// Injects an interrupt (equivalent to pressing Ctrl+C in the terminal).
    public func sendInterrupt() throws {
        try write(Data([0x03])) // ASCII ETX (\u{03})
    }
    
    /// Injects an EOF character (equivalent to Ctrl+D).
    public func sendEOF() throws {
        try write(Data([0x04])) // ASCII EOT (\u{04})
    }
    
    /// Updates the terminal window size and triggers SIGWINCH in the child process.
    public func resize(dimensions: TerminalDimensions) throws {
        guard masterFD != -1 else { throw PTYError.invalidFileDescriptor }
        var ws = winsize(
            ws_row: UInt16(dimensions.rows),
            ws_col: UInt16(dimensions.cols),
            ws_xpixel: UInt16(dimensions.pixelWidth),
            ws_ypixel: UInt16(dimensions.pixelHeight)
        )
        if ioctl(masterFD, TIOCSWINSZ, &ws) == -1 {
            throw PTYError.ioctlFailed(errno: errno)
        }
    }
    
    /// Asynchronously waits for process termination without blocking threads.
    public func waitUntilExit() async -> Int32 {
        if !process.isRunning {
            return process.terminationStatus
        }
        return await withCheckedContinuation { continuation in
            self.exitContinuation = continuation
            self.process.terminationHandler = { [weak self] proc in
                Task { [weak self] in
                    await self?.handleTermination(status: proc.terminationStatus)
                }
            }
        }
    }
    
    private func handleTermination(status: Int32) {
        exitContinuation?.resume(returning: status)
        exitContinuation = nil
        readSource?.cancel()
    }
    
    /// Gracefully stops the process, escalating from SIGINT -> SIGTERM -> SIGKILL.
    public func terminateGracefully() async {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        
        // 1. Send Ctrl+C
        try? sendInterrupt()
        
        // Wait up to 1 second
        for _ in 0..<10 {
            if !process.isRunning { return }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // 2. Send SIGTERM to process group
        kill(-pid, SIGTERM)
        
        // Wait up to 1.5 seconds
        for _ in 0..<15 {
            if !process.isRunning { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // 3. Force kill process group with SIGKILL
        if process.isRunning {
            kill(-pid, SIGKILL)
        }
    }
    
    deinit {
        readSource?.cancel()
        if process.isRunning {
            let pid = process.processIdentifier
            kill(-pid, SIGKILL)
        }
    }
}
```

---

## 7. SwarmDeck Architecture Integration

This `PTYProcess` design directly satisfies SwarmDeck's core system requirements:

1. **Embedding into `libghostty`:**
   * Ghostty's input feed takes raw binary terminal data. As chunks arrive from `pty.outputStream`, they are yielded directly to `ghostty_surface_write(surface, data)`.
   * User keystrokes received by the SwiftUI/Ghostty view are routed to `await pty.write(keystrokeData)`.
   * When SwiftUI view bounds update, calling `await pty.resize(dimensions:)` ensures Ghostty and the underlying process stay in lockstep.

2. **Hooking into Background Agent State Monitoring:**
   * Because `outputStream` is an `AsyncStream<Data>`, a background monitoring task (`Task.detached(priority: .utility)`) can consume a tee/branch of the stream or inspect data chunks for state detection regexes (e.g., prompt indicators, approval requests, idle badges) without blocking or delaying the UI rendering pipeline.

---

## 8. Summary Checklist for SwarmDeck PTY Implementation

| Requirement | Implementation | Rationale |
| :--- | :--- | :--- |
| **PTY Allocation** | `openpty(&m, &s, nil, nil, &ws)` | Atomic BSD call, sets initial rows/cols, avoids verbose POSIX calls |
| **Slave Cleanup** | `close(slave)` right after `proc.run()` | Prevents parent from keeping slave open; ensures clean EOF/EIO on process exit |
| **Read Loop** | `DispatchSourceRead` with `O_NONBLOCK` | Avoids thread pool exhaustion; prevents `NSFileHandleOperationException` crash |
| **macOS EOF Handling** | Treat `errno == EIO` as EOF | Darwin kernel raises `EIO` on master when slave closes |
| **Descriptor Teardown** | Close `masterFD` in `setCancelHandler` | Avoids GCD race condition and `EBADDESC` panic |
| **Write Protection** | `signal(SIGPIPE, SIG_IGN)` | Prevents sudden application exit when writing to exited agent sessions |
| **Window Resizing** | `ioctl(masterFD, TIOCSWINSZ, &ws)` | Broadcasts `SIGWINCH` to foreground process group |
| **Session Cleanup** | `kill(-pid, SIGTERM)` / `SIGKILL` | Cleans up entire process tree, preventing orphaned node/python/git child processes |
