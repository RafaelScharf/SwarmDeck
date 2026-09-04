import Foundation
import Darwin

// MARK: - JSON-RPC Protocol Models

public struct IPCRequest: Codable, Sendable {
    public let id: String?
    public let method: String
    public let params: [String: String]?
    
    public init(id: String? = UUID().uuidString, method: String, params: [String: String]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct IPCError: Codable, Sendable {
    public let code: Int
    public let message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct IPCResponse: Codable, Sendable {
    public let id: String?
    public let result: String?
    public let error: IPCError?
    
    public init(id: String?, result: String?, error: IPCError? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
    
    public static func success(id: String?, result: String) -> IPCResponse {
        IPCResponse(id: id, result: result, error: nil)
    }
    
    public static func failure(id: String?, code: Int, message: String) -> IPCResponse {
        IPCResponse(id: id, result: nil, error: IPCError(code: code, message: message))
    }
}

// MARK: - Unix Domain Socket Server

public actor IPCServer {
    public static let shared = IPCServer()
    
    public let socketPath: String
    private var listeningFD: Int32 = -1
    private var isRunning = false
    private var clientDispatchSources: [Int32: DispatchSourceRead] = [:]
    private var acceptSource: DispatchSourceRead?
    
    public typealias RequestHandler = @Sendable (IPCRequest) async -> IPCResponse
    private var handler: RequestHandler?
    
    public init(socketPath: String? = nil) {
        if let path = socketPath {
            self.socketPath = path
        } else {
            self.socketPath = "/tmp/swarmdeck-\(getuid()).sock"
        }
    }
    
    public func setHandler(_ handler: @escaping RequestHandler) {
        self.handler = handler
    }
    
    public func start() throws {
        guard !isRunning else { return }
        
        // Remove stale socket file if present
        unlink(socketPath)
        
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to create UNIX socket"])
        }
        
        // Set non-blocking
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd)
            throw NSError(domain: "SwarmDeckIPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Socket path is too long"])
        }
        
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (idx, byte) in pathBytes.enumerated() {
                raw[idx] = byte
            }
        }
        
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, addrLen)
            }
        }
        
        guard bindResult == 0 else {
            let err = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to bind UNIX socket to \(socketPath)"])
        }
        
        guard Darwin.listen(fd, 16) == 0 else {
            let err = errno
            close(fd)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(err), userInfo: [NSLocalizedDescriptionKey: "Failed to listen on UNIX socket"])
        }
        
        self.listeningFD = fd
        self.isRunning = true
        
        // Setup DispatchSource for incoming connections
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        let server = self
        source.setEventHandler { [server] in
            Task {
                await server.acceptConnections()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.acceptSource = source
    }
    
    private func acceptConnections() {
        guard isRunning && listeningFD >= 0 else { return }
        
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        
        while true {
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(listeningFD, sockPtr, &clientLen)
                }
            }
            
            if clientFD < 0 {
                break // No more pending connections (EWOULDBLOCK)
            }
            
            // Set client non-blocking
            let flags = fcntl(clientFD, F_GETFL, 0)
            _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)
            
            handleClientConnection(clientFD)
        }
    }
    
    private func handleClientConnection(_ clientFD: Int32) {
        let readSource = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: DispatchQueue.global(qos: .userInitiated))
        var readBuffer = Data()
        
        let server = self
        readSource.setEventHandler { [server] in
            var tempBuffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientFD, &tempBuffer, tempBuffer.count)
            
            if bytesRead > 0 {
                readBuffer.append(tempBuffer, count: bytesRead)
                // Process newline-delimited messages
                while let newlineIndex = readBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let messageData = readBuffer.subdata(in: 0..<newlineIndex)
                    readBuffer.removeSubrange(0...newlineIndex)
                    
                    Task {
                        await server.processMessage(data: messageData, clientFD: clientFD)
                    }
                }
            } else if bytesRead == 0 || (bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                // Client disconnected
                readSource.cancel()
            }
        }
        
        readSource.setCancelHandler { [server] in
            close(clientFD)
            Task {
                await server.removeClientSource(clientFD)
            }
        }
        
        clientDispatchSources[clientFD] = readSource
        readSource.resume()
    }
    
    private func removeClientSource(_ fd: Int32) {
        clientDispatchSources.removeValue(forKey: fd)
    }
    
    private func processMessage(data: Data, clientFD: Int32) async {
        guard !data.isEmpty else { return }
        
        let response: IPCResponse
        do {
            let request = try JSONDecoder().decode(IPCRequest.self, from: data)
            if let handler = self.handler {
                response = await handler(request)
            } else {
                response = .failure(id: request.id, code: -32603, message: "Server handler not configured")
            }
        } catch {
            response = .failure(id: nil, code: -32700, message: "Invalid JSON-RPC payload: \(error.localizedDescription)")
        }
        
        if var encoded = try? JSONEncoder().encode(response) {
            encoded.append(UInt8(ascii: "\n"))
            encoded.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    _ = Darwin.write(clientFD, baseAddress, encoded.count)
                }
            }
        }
    }
    
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        
        acceptSource?.cancel()
        acceptSource = nil
        
        for (_, source) in clientDispatchSources {
            source.cancel()
        }
        clientDispatchSources.removeAll()
        
        if listeningFD >= 0 {
            close(listeningFD)
            listeningFD = -1
        }
        unlink(socketPath)
    }
    
    deinit {
        if listeningFD >= 0 {
            close(listeningFD)
        }
        unlink(socketPath)
    }
}

// MARK: - Unix Domain Socket Client Helper

public final class IPCClient: Sendable {
    public let socketPath: String
    
    public init(socketPath: String? = nil) {
        if let path = socketPath {
            self.socketPath = path
        } else {
            self.socketPath = "/tmp/swarmdeck-\(getuid()).sock"
        }
    }
    
    public func isServerRunning() -> Bool {
        guard FileManager.default.fileExists(atPath: socketPath) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (idx, byte) in pathBytes.enumerated() {
                raw[idx] = byte
            }
        }
        
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        return res == 0
    }
    
    public func sendRequest(_ request: IPCRequest, timeout: TimeInterval = 2.0) async throws -> IPCResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            for (idx, byte) in pathBytes.enumerated() {
                raw[idx] = byte
            }
        }
        
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        
        guard connectResult == 0 else {
            close(fd)
            throw NSError(domain: "SwarmDeckIPC", code: -1, userInfo: [NSLocalizedDescriptionKey: "SwarmDeck is not running or socket unavailable at \(socketPath)"])
        }
        
        var encoded = try JSONEncoder().encode(request)
        encoded.append(UInt8(ascii: "\n"))
        
        let writeRes = encoded.withUnsafeBytes { rawBuffer in
            Darwin.write(fd, rawBuffer.baseAddress!, encoded.count)
        }
        guard writeRes > 0 else {
            close(fd)
            throw NSError(domain: "SwarmDeckIPC", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to send request"])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let resolver = IPCCallbackResolver(continuation: continuation, fd: fd)
            
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler {
                resolver.finish(with: .failure(NSError(domain: "SwarmDeckIPC", code: -3, userInfo: [NSLocalizedDescriptionKey: "IPC request timed out"])))
                timer.cancel()
            }
            timer.resume()
            
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = Data()
                var chunk = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = read(fd, &chunk, chunk.count)
                    if count > 0 {
                        buffer.append(chunk, count: count)
                        if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                            let responseData = buffer.subdata(in: 0..<newlineIndex)
                            timer.cancel()
                            do {
                                let decoded = try JSONDecoder().decode(IPCResponse.self, from: responseData)
                                resolver.finish(with: .success(decoded))
                            } catch {
                                resolver.finish(with: .failure(error))
                            }
                            break
                        }
                    } else {
                        timer.cancel()
                        resolver.finish(with: .failure(NSError(domain: "SwarmDeckIPC", code: -4, userInfo: [NSLocalizedDescriptionKey: "Connection closed before response received"])))
                        break
                    }
                }
            }
        }
    }
}

private final class IPCCallbackResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<IPCResponse, Error>
    private let fd: Int32
    
    init(continuation: CheckedContinuation<IPCResponse, Error>, fd: Int32) {
        self.continuation = continuation
        self.fd = fd
    }
    
    func finish(with result: Result<IPCResponse, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        close(fd)
        continuation.resume(with: result)
    }
}
