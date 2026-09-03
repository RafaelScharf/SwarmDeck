import Foundation
import Darwin

class PTY {
    let masterFD: Int32
    private let slaveFD: Int32
    
    private var process: Process?
    private var readSource: DispatchSourceRead?
    
    var onData: ((Data) -> Void)?
    
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
            // Unset ECHO, ICANON to make it raw-like if necessary,
            // but zsh sets its own termios anyway.
        }
    }
    
    deinit {
        readSource?.cancel()
        if masterFD != -1 { close(masterFD) }
        if slaveFD != -1 { close(slaveFD) }
    }
    
    func spawn(executable: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        
        // Pass slave as stdin, stdout, stderr
        let handle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        proc.standardInput = handle
        proc.standardOutput = handle
        proc.standardError = handle
        
        // Setup environment
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color" // or ghostty
        env["COLORTERM"] = "truecolor"
        proc.environment = env
        
        self.process = proc
        
        startReading()
        
        try proc.run()
    }
    
    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = Darwin.read(self.masterFD, &buffer, bufferSize)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.onData?(data)
            } else if bytesRead == 0 {
                self.readSource?.cancel()
            }
        }
        self.readSource = source
        source.resume()
    }
    
    func writeToMaster(_ data: Data) {
        data.withUnsafeBytes { buffer in
            if let ptr = buffer.baseAddress {
                _ = Darwin.write(masterFD, ptr, buffer.count)
            }
        }
    }
    
    func resize(columns: Int, rows: Int, widthPixels: Int, heightPixels: Int) {
        var winSize = winsize(
            ws_row: UInt16(rows),
            ws_col: UInt16(columns),
            ws_xpixel: UInt16(widthPixels),
            ws_ypixel: UInt16(heightPixels)
        )
        ioctl(masterFD, TIOCSWINSZ, &winSize)
    }
}
