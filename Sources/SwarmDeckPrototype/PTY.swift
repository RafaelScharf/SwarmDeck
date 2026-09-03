import Foundation
import Darwin

actor PTY {
    let masterFD: Int32
    private let slaveFD: Int32
    
    private var process: Process?
    private var readTask: Task<Void, Never>?
    
    var onData: (@Sendable (Data) -> Void)?
    
    init() throws {
        var m: Int32 = 0
        var s: Int32 = 0
        if openpty(&m, &s, nil, nil, nil) == -1 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
        self.masterFD = m
        self.slaveFD = s
        
        var term = termios()
        if tcgetattr(slaveFD, &term) == 0 {
            // Unset ECHO, ICANON to make it raw-like if necessary
        }
    }
    
    deinit {
        readTask?.cancel()
        if masterFD != -1 { close(masterFD) }
        if slaveFD != -1 { close(slaveFD) }
    }
    
    func spawn(executable: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        
        let handle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        proc.standardInput = handle
        proc.standardOutput = handle
        proc.standardError = handle
        
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        proc.environment = env
        
        self.process = proc
        
        startReading()
        
        try proc.run()
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
