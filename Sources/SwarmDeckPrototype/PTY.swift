import Foundation
import Darwin

actor PTY {
    let masterFD: Int32
    private var childPID: pid_t = -1
    private var readTask: Task<Void, Never>?
    
    var onData: (@Sendable (Data) -> Void)?
    
    init() throws {
        var m: Int32 = 0
        let pid = forkpty(&m, nil, nil, nil)
        
        if pid == -1 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        } else if pid == 0 {
            // Child process
            let args = ["/bin/zsh", "-l"]
            var cArgs = args.map { strdup($0) }
            cArgs.append(nil)
            
            let env = ["TERM=xterm-256color", "COLORTERM=truecolor", "PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")", "HOME=\(ProcessInfo.processInfo.environment["HOME"] ?? "")"]
            var cEnv = env.map { strdup($0) }
            cEnv.append(nil)
            
            execve("/bin/zsh", &cArgs, &cEnv)
            exit(1)
        }
        
        // Parent process
        self.masterFD = m
        self.childPID = pid
    }
    
    deinit {
        readTask?.cancel()
        if masterFD != -1 { close(masterFD) }
        if childPID != -1 { kill(childPID, SIGTERM) }
    }
    
    func spawn(executable: String, arguments: [String]) throws {
        // Spawning is already handled by forkpty in init() for this prototype
        // to ensure the controlling terminal is set up properly.
        startReading()
    }
    
    func setOnData(_ handler: @escaping @Sendable (Data) -> Void) {
        self.onData = handler
    }
    
    private func startReading() {
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
        data.withUnsafeBytes { buffer in
            if let ptr = buffer.baseAddress {
                _ = Darwin.write(masterFD, ptr, buffer.count)
            }
        }
    }
    
    nonisolated func resize(columns: Int, rows: Int, widthPixels: Int, heightPixels: Int) {
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: UInt16(widthPixels),
            ws_ypixel: UInt16(heightPixels)
        )
        ioctl(masterFD, TIOCSWINSZ, &winSize)
    }
}
